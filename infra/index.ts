import * as pulumi from "@pulumi/pulumi";
import * as azure from "@pulumi/azure-native";

// Configuration
const config = new pulumi.Config();
const location = config.get("location") || "australiaeast";
const env = config.require("env");
const adminUser = config.get("adminUser") || "dip-user";
const sshPublicKey = config.requireSecret("sshPublicKey");

// Constants
const aksSubnetCidr = "10.240.0.0/20";
const sqlSubnetCidr = "10.240.16.0/24";
// const overlayPodCidr = "10.0.192.0/18";

const defaultTags = {
    Environment: env,
    ManagedBy: "Pulumi",
};

const identityName = "dip-aks-identity";
const networkContributorRoleGuid = '4d97b98b-1d4f-4787-a291-c67834d212e7';
const aksClusterAdminRoleGuid = 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b';

// Get current resource group
const resourceGroup = pulumi.output(azure.resources.getResourceGroup({
    resourceGroupName: config.require("resourceGroup")
}));

// User Assigned Identity
const userAssignedIdentity = new azure.managedidentity.UserAssignedIdentity("aksIdentity", {
    resourceName: identityName,
    location: location,
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
});

// Network Contributor Role Assignment
const networkRoleAssignment = new azure.authorization.RoleAssignment("networkRoleAssignment", {
    scope: resourceGroup.id,
    roleDefinitionId: pulumi.interpolate`/subscriptions/${azure.authorization.getClientConfig().then(c => c.subscriptionId)}/providers/Microsoft.Authorization/roleDefinitions/${networkContributorRoleGuid}`,
    principalId: userAssignedIdentity.principalId,
    principalType: "ServicePrincipal",
});

// Network Security Group
const aksNsg = new azure.network.NetworkSecurityGroup("aksNsg", {
    networkSecurityGroupName: "dip-k8s-nsg",
    location: location,
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
    securityRules: [
        
    ],
});

// Virtual Network
const vnet = new azure.network.VirtualNetwork("vnet", {
    virtualNetworkName: "dip-vnet",
    location: location,
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
    addressSpace: {
        addressPrefixes: ["10.240.0.0/16"],
    },
    subnets: [
        {
            name: "aks-subnet",
            addressPrefix: aksSubnetCidr,
            networkSecurityGroup: {
                id: aksNsg.id,
            },
        },
        {
            name: "sql-subnet",
            addressPrefix: sqlSubnetCidr,
            privateEndpointNetworkPolicies: "Disabled",
            privateLinkServiceNetworkPolicies: "Enabled",
        },
    ],
});

// AKS Cluster
const aks = new azure.containerservice.ManagedCluster("aksCluster", {
    resourceName: "dip-pipeline-win-aks",
    location: location,
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
    sku: {
        name: "Base",
        tier: "Free",
    },
    identity: {
        type: "UserAssigned",
        userAssignedIdentities: 
            [userAssignedIdentity.id]
    },
    kubernetesVersion: "1.33",
    dnsPrefix: "dip-win-aks-dns",
    nodeResourceGroup: pulumi.interpolate`${resourceGroup.name}-node-rg`,
    disableLocalAccounts: true,
    enableRBAC: true,
    aadProfile: {
        managed: true,
        enableAzureRBAC: true,
    },
    networkProfile: {
        networkPlugin: "azure",
        networkPluginMode: "overlay",
        networkPolicy: "calico",
        outboundType: "loadBalancer",
        loadBalancerSku: "standard",
        networkDataplane: "azure",
        loadBalancerProfile: {
            managedOutboundIPs: {
                count: 1,
            },
        },
    },
    apiServerAccessProfile: {
        enablePrivateCluster: false,
    },
    agentPoolProfiles: [
        {
            name: "tempsystem",
            count: 1,
            minCount: 1,
            maxCount: 1,
            enableAutoScaling: true,
            vmSize: "Standard_E4ads_v5",
            osType: "Linux",
            osDiskType: "Ephemeral",
            osDiskSizeGB: 150,
            vnetSubnetID: vnet.subnets.apply(subnet => subnet![0]!.id!),
            availabilityZones: ["1", "2", "3"],
            mode: "System",
            type: "VirtualMachineScaleSets",
            maxPods: 250,
            nodeTaints: ["CriticalAddonsOnly=true:NoSchedule"],
            tags: defaultTags,
        },
    ],
    linuxProfile: {
        adminUsername: adminUser,
        ssh: {
            publicKeys: [
                {
                    keyData: sshPublicKey,
                },
            ],
        },
    },
    autoUpgradeProfile: {
        upgradeChannel: "none",
        nodeOSUpgradeChannel: "NodeImage",
    },
    autoScalerProfile: {
        maxGracefulTerminationSec: "1800",
        daemonsetEvictionForEmptyNodes: true,
        daemonsetEvictionForOccupiedNodes: true,
    },
    addonProfiles: {
        azureKeyvaultSecretsProvider: {
            enabled: true,
            config: {
                enableSecretRotation: "true",
            },
        },
        azurepolicy: {
            enabled: true,
            config: {
                version: "v2",
            },
        },
    },
    workloadAutoScalerProfile: {
        keda: {
            enabled: true,
        },
    },
    serviceMeshProfile: {
        mode: "Istio",
        istio: {
            components: {
                ingressGateways: [
                    {
                        enabled: true,
                        mode: "External",
                    },
                ],
            },
            revisions: ["asm-1-26"],
        },
    },
    oidcIssuerProfile: {
        enabled: true,
    },
    securityProfile: {
        workloadIdentity: {
            enabled: true,
        },
    },
}, { dependsOn: [networkRoleAssignment] });

// Get current Azure client config
const currentUser = azure.authorization.getClientConfig();

// AKS Cluster Admin Role Assignment for current user
const aksClusterAdminRoleAssignment = new azure.authorization.RoleAssignment("aksClusterAdminRoleAssignment", {
    scope: aks.id,
    roleDefinitionId: pulumi.interpolate`/subscriptions/${currentUser.then(c => c.subscriptionId)}/providers/Microsoft.Authorization/roleDefinitions/${aksClusterAdminRoleGuid}`,
    principalId: currentUser.then(c => c.objectId),
    principalType: "User",
});

// Windows Agent Pool
const windowsAgentPool = new azure.containerservice.AgentPool("windowsAgentPool", {
    agentPoolName: "win01",
    resourceName: aks.name,
    resourceGroupName: resourceGroup.name,
    count: 5,
    minCount: 5,
    maxCount: 10,
    enableAutoScaling: true,
    vmSize: "Standard_D4ads_v5",
    osType: "Windows",
    osDiskType: "Ephemeral",
    osDiskSizeGB: 150,
    vnetSubnetID: vnet.subnets.apply(subnet => subnet![0]!.id!),
    availabilityZones: ["1", "2", "3"],
    mode: "User",
    type: "VirtualMachineScaleSets",
    maxPods: 30,
    tags: defaultTags,
}, { dependsOn: [aks] });

// Linux Agent Pool
const linuxAgentPool = new azure.containerservice.AgentPool("linuxAgentPool", {
    agentPoolName: "linux01",
    resourceName: aks.name,
    resourceGroupName: resourceGroup.name,
    count: 1,
    minCount: 1,
    maxCount: 10,
    enableAutoScaling: true,
    vmSize: "Standard_D4ads_v5",
    osType: "Linux",
    osDiskType: "Ephemeral",
    osDiskSizeGB: 150,
    vnetSubnetID: vnet.subnets.apply(subnet => subnet![0]!.id!),
    availabilityZones: ["1", "2", "3"],
    mode: "User",
    type: "VirtualMachineScaleSets",
    maxPods: 250,
    tags: defaultTags,
}, { dependsOn: [aks] });

// SQL Server
const sqlAdminLogin = config.get("sqlAdminLogin") || "sqladmin";
const sqlAdminPassword = config.requireSecret("sqlAdminPassword");

const sqlServer = new azure.sql.Server("sqlServer", {
    serverName: pulumi.interpolate`dip-sql-${env}`,
    location: location,
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
    administratorLogin: sqlAdminLogin,
    administratorLoginPassword: sqlAdminPassword,
    version: "12.0",
    minimalTlsVersion: "1.2",
    publicNetworkAccess: "Disabled",
});

// SQL Database
const sqlDatabase = new azure.sql.Database("sqlDatabase", {
    databaseName: "dip-database",
    location: location,
    resourceGroupName: resourceGroup.name,
    serverName: sqlServer.name,
    tags: defaultTags,
    sku: {
        name: "GP_S_Gen5_2",
        tier: "GeneralPurpose",
    },
    autoPauseDelay: 60,
    minCapacity: 0.5,
});

// Private DNS Zone for SQL
const sqlPrivateDnsZone = new azure.privatedns.PrivateZone("sqlPrivateDnsZone", {
    privateZoneName: "privatelink.database.windows.net",
    location: "global",
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
});

// Link Private DNS Zone to VNet
const sqlDnsZoneLink = new azure.privatedns.VirtualNetworkLink("sqlDnsZoneLink", {
    virtualNetworkLinkName: "sql-vnet-link",
    resourceGroupName: resourceGroup.name,
    privateZoneName: sqlPrivateDnsZone.name,
    location: "global",
    virtualNetwork: {
        id: vnet.id,
    },
    registrationEnabled: false,
    tags: defaultTags,
});

// Private Endpoint for SQL Server
const sqlPrivateEndpoint = new azure.network.PrivateEndpoint("sqlPrivateEndpoint", {
    privateEndpointName: "sql-private-endpoint",
    location: location,
    resourceGroupName: resourceGroup.name,
    tags: defaultTags,
    subnet: {
        id: vnet.subnets.apply(subnets => subnets![1]!.id!),
    },
    privateLinkServiceConnections: [
        {
            name: "sql-connection",
            privateLinkServiceId: sqlServer.id,
            groupIds: ["sqlServer"],
        },
    ],
});

// Private DNS Zone Group
const sqlPrivateDnsZoneGroup = new azure.network.PrivateDnsZoneGroup("sqlPrivateDnsZoneGroup", {
    privateDnsZoneGroupName: "default",
    resourceGroupName: resourceGroup.name,
    privateEndpointName: sqlPrivateEndpoint.name,
    privateDnsZoneConfigs: [
        {
            name: "sql-config",
            privateDnsZoneId: sqlPrivateDnsZone.id,
        },
    ],
});

// Exports
export const clusterName = aks.name;
export const clusterId = aks.id;
export const vnetId = vnet.id;
export const nsgId = aksNsg.id;
export const sqlServerId = sqlServer.id;
export const sqlServerName = sqlServer.name;
export const sqlDatabaseName = sqlDatabase.name;
export const sqlPrivateEndpointId = sqlPrivateEndpoint.id;
