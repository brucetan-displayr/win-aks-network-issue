using k8s;
using k8s.Models;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;

var mode = Environment.GetEnvironmentVariable("MODE")?.ToLower() ?? "runner";

Console.WriteLine($"Starting application in {mode.ToUpper()} mode...");

if (mode == "orchestrator")
{
    await RunOrchestratorMode();
}
else if (mode == "runner")
{
    await RunRunnerMode();
}
else
{
    Console.WriteLine($"ERROR: Invalid MODE '{mode}'. Must be 'orchestrator' or 'runner'.");
    Environment.Exit(1);
}

async Task RunOrchestratorMode()
{
    Console.WriteLine("Orchestrator mode: Creating Kubernetes jobs...");
    
    var config = KubernetesClientConfiguration.InClusterConfig();
    var client = new Kubernetes(config);
    
    // Validate that CONN_STR exists (even though we'll reference it as a secret in jobs)
    var connectionString = Environment.GetEnvironmentVariable("CONN_STR");
    if (string.IsNullOrEmpty(connectionString))
    {
        Console.WriteLine("ERROR: CONN_STR environment variable is required in orchestrator mode.");
        Environment.Exit(1);
    }

    var imageName = Environment.GetEnvironmentVariable("IMAGE_NAME");
    if (string.IsNullOrEmpty(imageName))
    {
        Console.WriteLine("ERROR: IMAGE_NAME environment variable is required in orchestrator mode.");
        Environment.Exit(1);
    }

    var namespaceParam = Environment.GetEnvironmentVariable("NAMESPACE") ?? "default";
    var secretName = Environment.GetEnvironmentVariable("SECRET_NAME") ?? "sql-connection-secret";

    // Get number of jobs from env var, default to 50
    var jobsEnv = Environment.GetEnvironmentVariable("ORCHESTRATOR_NUM_JOBS");
    int numJobs = 50;
    if (!string.IsNullOrEmpty(jobsEnv) && int.TryParse(jobsEnv, out var parsedJobs) && parsedJobs > 0)
    {
        numJobs = parsedJobs;
    }

    var batchWaitSecondsEnv = Environment.GetEnvironmentVariable("ORCHESTRATOR_BATCH_WAIT_SECONDS");
    int batchWaitSeconds = 60;
    if (!string.IsNullOrEmpty(batchWaitSecondsEnv) && int.TryParse(batchWaitSecondsEnv, out var parsedBatchWaitSeconds) && parsedBatchWaitSeconds > 0)
    {
        batchWaitSeconds = parsedBatchWaitSeconds;
    }

    while (true)
    {
        try
        {

            try
            {
                var secret = await client.ReadNamespacedSecretAsync(secretName, namespaceParam);
            }
            catch (k8s.Autorest.HttpOperationException ex) when (ex.Response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                throw new Exception($"ERROR: Kubernetes secret '{secretName}' not found in namespace '{namespaceParam}'. Jobs will not be created.");
            }

            Console.WriteLine($"Creating {numJobs} jobs at {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC...");
            
            var timestamp = DateTime.UtcNow.ToString("yyyyMMddHHmmss");
            var tasks = new List<Task>();

            for (int i = 0; i < numJobs; i++)
            {
                var jobNumber = i + 1;
                var jobName = $"sql-runner-{timestamp}-{jobNumber}";
                
                var job = new V1Job
                {
                    ApiVersion = "batch/v1",
                    Kind = "Job",
                    Metadata = new V1ObjectMeta
                    {
                        Name = jobName,
                        Labels = new Dictionary<string, string>
                        {
                            { "app", "sql-runner" },
                            { "batch", timestamp }
                        }
                    },
                    Spec = new V1JobSpec
                    {
                        BackoffLimit = 0,
                        TtlSecondsAfterFinished = 300, // Clean up after 5 minutes
                        Template = new V1PodTemplateSpec
                        {
                            Metadata = new V1ObjectMeta
                            {
                                Labels = new Dictionary<string, string>
                                {
                                    { "app", "sql-runner" },
                                    { "batch", timestamp }
                                }
                            },
                            Spec = new V1PodSpec
                            {
                                RestartPolicy = "Never",
                                // Dynamically set node selector based on current OS
                                NodeSelector = new Dictionary<string, string>
                                {
                                    { "kubernetes.io/os",
                                        Environment.OSVersion.Platform == PlatformID.Win32NT ? "windows" : "linux"
                                    }
                                },
                                Containers = new List<V1Container>
                                {
                                    new V1Container
                                    {
                                        Name = "sql-runner",
                                        Image = imageName,
                                        Env = new List<V1EnvVar>
                                        {
                                            new V1EnvVar { Name = "MODE", Value = "runner" },
                                            new V1EnvVar { Name = "RUNNER_DURATION_MINS", Value= Environment.GetEnvironmentVariable("RUNNER_DURATION_MINS") ?? "" },
                                            new V1EnvVar { Name = "RUNNER_SQL_WAIT_SECONDS", Value= Environment.GetEnvironmentVariable("RUNNER_SQL_WAIT_SECONDS") ?? "" },

                                            // Reference the secret instead of passing value directly for security
                                            new V1EnvVar 
                                            { 
                                                Name = "CONN_STR",
                                                ValueFrom = new V1EnvVarSource
                                                {
                                                    SecretKeyRef = new V1SecretKeySelector
                                                    {
                                                        Name = secretName,
                                                        Key = "CONN_STR"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                };

                // Create job asynchronously
                tasks.Add(CreateJobAsync(client, namespaceParam, job, jobName));
            }

            await Task.WhenAll(tasks);
            Console.WriteLine($"Successfully created {numJobs} jobs in batch {timestamp}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR creating jobs: {ex.Message}");
        }

        // Wait 1 minute before creating next batch
        Console.WriteLine($"Waiting {batchWaitSeconds} seconds before creating next batch...");
        await Task.Delay(TimeSpan.FromSeconds(batchWaitSeconds));
    }
}

async Task CreateJobAsync(Kubernetes client, string namespaceParam, V1Job job, string jobName)
{
    try
    {
        await client.CreateNamespacedJobAsync(job, namespaceParam);
        Console.WriteLine($"Created job: {jobName}");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"ERROR creating job {jobName}: {ex.Message}");
    }
}

async Task RunRunnerMode()
{
    Console.WriteLine("Runner mode: Starting API server and executing SQL queries via API...");
    
    var connectionString = Environment.GetEnvironmentVariable("CONN_STR");
    if (string.IsNullOrEmpty(connectionString))
    {
        Console.WriteLine("ERROR: CONN_STR environment variable is required.");
        Environment.Exit(1);
    }

    // Configure connection pooling in connection string
    var builder = new SqlConnectionStringBuilder(connectionString)
    {
        Pooling = true,
        MinPoolSize = 5,
        MaxPoolSize = 100,
        ConnectTimeout = 30
    };
    var pooledConnectionString = builder.ConnectionString;

    // Get runner duration from env var, default to 1 minute
    var durationEnv = Environment.GetEnvironmentVariable("RUNNER_DURATION_MINS");
    int runnerMinutes = 1;
    if (!string.IsNullOrEmpty(durationEnv) && int.TryParse(durationEnv, out var parsedMinutes) && parsedMinutes > 0)
    {
        runnerMinutes = parsedMinutes;
    }

    var runnerSqlWaitEnv = Environment.GetEnvironmentVariable("RUNNER_SQL_WAIT_SECONDS");
    int sqlWaitSeconds = 10;
    if (!string.IsNullOrEmpty(runnerSqlWaitEnv) && int.TryParse(runnerSqlWaitEnv, out var parsedSqlWaitSeconds) && parsedSqlWaitSeconds > 0)
    {
        sqlWaitSeconds = parsedSqlWaitSeconds;
    }

    // Build minimal API
    var builder2 = WebApplication.CreateBuilder();
    builder2.WebHost.UseUrls("http://localhost:5000");
    var app = builder2.Build();

    // API endpoint to execute SQL query
    app.MapGet("/query", async () =>
    {
        try
        {
            using var connection = new SqlConnection(pooledConnectionString);
            await connection.OpenAsync();
            using var command = new SqlCommand("SELECT GETDATE();", connection);
            var result = await command.ExecuteScalarAsync();
            return Results.Ok(new { timestamp = result?.ToString(), status = "success" });
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR in API executing query: {ex.Message}");
            return Results.Problem(ex.Message, statusCode: 500);
        }
    });

    // Start the API server in background
    var apiTask = app.RunAsync();
    Console.WriteLine("API server started on http://localhost:5000");

    // Wait a bit for API to start
    await Task.Delay(2000);

    // Now make HTTP calls to the API
    var startTime = DateTime.UtcNow;
    var endTime = startTime.AddMinutes(runnerMinutes);
    var queryCount = 0;

    Console.WriteLine($"Starting API query execution for {runnerMinutes} minute(s) (until {endTime:yyyy-MM-dd HH:mm:ss} UTC)...");

    using var httpClient = new HttpClient();
    httpClient.BaseAddress = new Uri("http://localhost:5000");
    httpClient.Timeout = TimeSpan.FromSeconds(30);

    while (DateTime.UtcNow < endTime)
    {
        try
        {
            var response = await httpClient.GetAsync("/query");
            response.EnsureSuccessStatusCode();
            var content = await response.Content.ReadAsStringAsync();
            
            queryCount++;
            Console.WriteLine($"Query {queryCount}: {content}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR calling API: {ex.Message}");
        }

        // Wait before next query
        await Task.Delay(TimeSpan.FromSeconds(sqlWaitSeconds));
    }

    Console.WriteLine($"Runner completed. Executed {queryCount} queries in {runnerMinutes} minute(s).");
    
    // Stop the API server
    await app.StopAsync();
}
