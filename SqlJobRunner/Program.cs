using k8s;
using k8s.Models;
using Microsoft.Data.SqlClient;

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

    while (true)
    {
        try
        {
            Console.WriteLine($"Creating 50 jobs at {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC...");
            
            var timestamp = DateTime.UtcNow.ToString("yyyyMMddHHmmss");
            var tasks = new List<Task>();

            for (int i = 0; i < 50; i++)
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
                                Containers = new List<V1Container>
                                {
                                    new V1Container
                                    {
                                        Name = "sql-runner",
                                        Image = imageName,
                                        Env = new List<V1EnvVar>
                                        {
                                            new V1EnvVar { Name = "MODE", Value = "runner" },
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
            Console.WriteLine($"Successfully created 50 jobs in batch {timestamp}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR creating jobs: {ex.Message}");
        }

        // Wait 1 minute before creating next batch
        Console.WriteLine("Waiting 60 seconds before creating next batch...");
        await Task.Delay(TimeSpan.FromMinutes(1));
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
    Console.WriteLine("Runner mode: Executing SQL queries...");
    
    var connectionString = Environment.GetEnvironmentVariable("CONN_STR");
    if (string.IsNullOrEmpty(connectionString))
    {
        Console.WriteLine("ERROR: CONN_STR environment variable is required.");
        Environment.Exit(1);
    }

    var startTime = DateTime.UtcNow;
    var endTime = startTime.AddMinutes(1);
    var queryCount = 0;

    Console.WriteLine($"Starting SQL query execution for 1 minute (until {endTime:yyyy-MM-dd HH:mm:ss} UTC)...");

    while (DateTime.UtcNow < endTime)
    {
        try
        {
            using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync();
            
            using var command = new SqlCommand("SELECT COUNT(1) FROM [SalesLT].[Customer]", connection);
            var result = await command.ExecuteScalarAsync();
            
            queryCount++;
            Console.WriteLine($"Query {queryCount}: {result}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR executing query: {ex.Message}");
        }

        // Wait 1 second before next query
        await Task.Delay(TimeSpan.FromSeconds(1));
    }

    Console.WriteLine($"Runner completed. Executed {queryCount} queries in 1 minute.");
}
