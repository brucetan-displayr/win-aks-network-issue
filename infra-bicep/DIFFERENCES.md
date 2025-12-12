# Differences Between Pulumi TypeScript and Bicep Implementation

This document outlines the key differences between the original `windows-aks-resource.ts` Pulumi implementation and the Bicep template.

## Structural Differences

### 1. **Modularization**

**Pulumi (TypeScript)**:

- Single class `WindowsAksResource` that creates all resources
- References external stack outputs via `ConnectivityStackRef`
- Strongly typed with TypeScript interfaces

**Bicep**:

- Separated into multiple modules for better organization:
  - `main.bicep` - Entry point
  - `connectivity.bicep` - vWAN, Hub, Shared VNet
  - `spoke-networking.bicep` - Spoke VNet and subnets
  - `dns-zones.bicep` - Private DNS zones
  - `aks-identity.bicep` - User assigned identity
  - `windows-aks.bicep` - AKS cluster and agent pools
  - `role-assignments.bicep` - RBAC assignments
  - `monitoring.bicep` - Alerts and monitoring

### 2. **Parameter Passing**

**Pulumi (TypeScript)**:

```typescript
export type AksResourceArgs = {
  subscriptionId: Output<string>;
  resourceGroupName: Output<string>;
  // ... Uses Pulumi Output<T> for async values
};
```

**Bicep**:

```bicep
@description('Subscription ID')
param subscriptionId string = subscription().subscriptionId

// Uses ARM template parameters with decorators
```

### 3. **State Management**

**Pulumi (TypeScript)**:

- State stored in Pulumi backend (cloud or local)
- Cross-stack references via `StackReference`
- Automatic dependency tracking

**Bicep**:

- State stored in Azure Resource Manager
- No built-in cross-deployment references
- Manual dependency specification via `dependsOn`

## Feature Differences

### 1. **Connectivity Resources**

**Pulumi (TypeScript)**:

- References existing connectivity stack: `ConnectivityStackRef.getOutput('AksPrivateDnsZones')`
- Assumes connectivity resources are already deployed
- Uses outputs from separate deployment

**Bicep**:

- Creates all connectivity resources in same template
- Includes vWAN, Hub, Shared VNet creation
- Self-contained deployment

### 2. **DNS Zone Management**

**Pulumi (TypeScript)**:

```typescript
const aksPrivateDnsZoneIds = ConnectivityStackRef.getOutput('AksPrivateDnsZones') as Record<
  string,
  Record<string, Output<string>>
>;
```

**Bicep**:

```bicep
resource aksPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${environment}.privatelink.${region}.azmk8s.io'
  // Creates DNS zone in same deployment
}
```

### 3. **Agent Pool Management**

**Pulumi (TypeScript)**:

- Uses preview provider for artifact streaming: `@pulumi/azure-native_containerservice_v20250602preview`
- Dynamic pool creation based on `aksConfig.userPools`
- Conditional pool creation with TypeScript logic

**Bicep**:

- Uses GA API version: `@2024-09-02-preview`
- Static pool definitions (can be parameterized)
- Explicit resource definitions for each pool

### 4. **Resource Naming**

**Pulumi (TypeScript)**:

```typescript
this.namePrefix = `${platformNamePrefix}-${regionAbbreviation}-${spokeId}`;
// Dynamic based on base class properties
```

**Bicep**:

```bicep
var spokeNamePrefix = '${platformNamePrefix}-${regionAbbreviation}-${spokeId}'
// Computed from parameters
```

### 5. **Hooks and Custom Logic**

**Pulumi (TypeScript)**:

```typescript
const [beforeCreateHook, beforeUpdateHook] = createManagedClusterResourceHooks(
  `${this.namePrefix}-win`,
  isFirstDeployment
);
// Custom hooks for validation
```

**Bicep**:

- No built-in hooks mechanism
- Relies on deployment script for validation
- Can use deployment scripts for custom logic

### 6. **SignalFx Detectors**

**Pulumi (TypeScript)**:

- Creates SignalFx detectors directly in code
- Includes complex detector logic with programmatic configuration
- Uses `@pulumi/signalfx` provider

**Bicep**:

- Only includes Azure Monitor metric alerts
- SignalFx detectors would need separate deployment
- Focused on native Azure monitoring

## Missing Features in Bicep (vs Pulumi)

### 1. **SignalFx Integration**

- Container restart count detector
- Node not ready detector
- Node memory utilization detector
- Deployment not at spec detector

**Workaround**: Deploy SignalFx detectors separately or use Azure Monitor alternatives

### 2. **Dynamic Configuration**

The Pulumi version uses `AksConfig` for flexible pool configuration:

```typescript
export type AksConfig = {
  userPools: AksUserAgentPoolConfig[];
  isFirstDeployment?: boolean;
};
```

**Workaround**: In Bicep, create parameterized modules or use Bicep loops for dynamic pools

### 3. **Stack References**

Pulumi can reference outputs from other stacks:

```typescript
export const ConnectivityStackRef = new StackReference(
  `${OrgName}/dip-connectivity/connectivity.eus`
);
```

**Workaround**: Use Azure Resource Manager references or pass values as parameters

### 4. **Programming Language Features**

- No TypeScript type checking
- Limited conditional logic
- No loops over complex objects (without workarounds)

### 5. **Extension Installation**

Pulumi uses: `Extension` resource from `@pulumi/azure-native/kubernetesconfiguration`

Bicep uses: `Microsoft.KubernetesConfiguration/extensions@2023-05-01`

Both are equivalent but Bicep has no IDE warnings for deprecated properties.

## Advantages of Bicep Version

### 1. **Native Azure Integration**

- No external state management
- Works directly with Azure Resource Manager
- Better integration with Azure Portal

### 2. **Simpler Deployment**

- No Pulumi CLI required
- Standard Azure CLI commands
- Easier for teams familiar with ARM templates

### 3. **What-If Analysis**

```bash
az deployment sub what-if --template-file main.bicep
```

Shows changes before deployment (Pulumi preview is similar)

### 4. **No External Dependencies**

- No Node.js or package dependencies
- No Pulumi backend configuration
- Self-contained template files

### 5. **Modular Structure**

- Clear separation of concerns
- Reusable modules
- Easier to understand and maintain

## Advantages of Pulumi Version

### 1. **Programming Language**

- Full TypeScript/JavaScript capabilities
- Type safety and IntelliSense
- Reusable functions and classes

### 2. **Complex Logic**

- Easy loops and conditionals
- Dynamic resource creation
- Custom validation logic

### 3. **Multi-Cloud**

- Same tool for Azure, AWS, GCP
- Consistent deployment workflow
- Cross-cloud resource management

### 4. **Stack Outputs**

- Easy reference between deployments
- Type-safe output consumption
- Automatic dependency tracking

### 5. **Rich Ecosystem**

- Many providers (SignalFx, DataDog, etc.)
- Community packages
- Pulumi Crosswalk libraries

## Recommendations

### Use Bicep When:

- Team prefers native Azure tools
- No need for multi-cloud deployment
- Simpler infrastructure requirements
- Want to avoid external state management
- Azure-only shop with ARM template experience

### Use Pulumi When:

- Need multi-cloud support
- Complex conditional logic required
- Want programming language features
- Need to integrate with external services (SignalFx, PagerDuty)
- Want strong typing and IDE support
- Have existing Pulumi infrastructure

## Migration Path

### From Pulumi to Bicep:

1. Export Pulumi stack outputs
2. Convert to Bicep parameters
3. Deploy Bicep templates
4. Verify resources match
5. Update CI/CD pipelines

### From Bicep to Pulumi:

1. Import existing resources into Pulumi state
2. Convert Bicep to Pulumi code
3. Run Pulumi preview to verify
4. Deploy with Pulumi
5. Remove Bicep deployments

## Conclusion

Both implementations achieve the same infrastructure outcome. The choice depends on:

- Team expertise and preferences
- Existing tooling and workflows
- Multi-cloud requirements
- Complexity of infrastructure logic
- Integration needs with external services

The Bicep version provides a complete, self-contained deployment that's easier to understand but lacks some advanced monitoring features from the Pulumi version. These can be added separately or via Azure Monitor alternatives.
