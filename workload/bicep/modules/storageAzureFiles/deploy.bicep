targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

@sys.description('AVD workload subscription ID, multiple subscriptions scenario.')
param workloadSubsId string

@sys.description('Resource Group Name for Azure Files.')
param storageObjectsRgName string

@sys.description('Required, The service providing domain services for Azure Virtual Desktop.')
param identityServiceProvider string

@sys.description('Resource Group Name for management VM.')
param serviceObjectsRgName string

@sys.description('Storage account name.')
param storageAccountName string

@sys.description('Storage account file share name.')
param fileShareName string

@sys.description('Private endpoint subnet ID.')
param privateEndpointSubnetId string

@sys.description('Location where to deploy compute services.')
param sessionHostLocation string

@sys.description('File share SMB multichannel.')
param fileShareMultichannel bool

@sys.description('AD domain name.')
param identityDomainName string

@sys.description('AD domain GUID.')
param identityDomainGuid string

@sys.description('Keyvault name to get credentials from.')
param wrklKvName string

@sys.description('AVD session host domain join credentials.')
param domainJoinUserName string

@sys.description('AVD session host domain join credentials.')
@secure()
param domainJoinUserPassword string

@sys.description('Azure Files storage account SKU.')
param storageSku string

@sys.description('*Azure File share quota')
param fileShareQuotaSize int

@sys.description('Use Azure private DNS zones for private endpoints.')
param vnetPrivateDnsZoneFilesId string

//@sys.description('Script name for adding storage account to Active Directory.')
//param storageToDomainScript string

//@sys.description('URI for the script for adding the storage account to Active Directory.')
//param storageToDomainScriptUri string

@sys.description('Tags to be applied to resources')
param tags object

@sys.description('Name for management virtual machine. for tools and to join Azure Files to domain.')
param managementVmName string

@sys.description('Optional. AVD Accelerator will deploy with private endpoints by default.')
param deployPrivateEndpoint bool

@sys.description('Log analytics workspace for diagnostic logs.')
param alaWorkspaceResourceId string

@sys.description('Diagnostic logs retention.')
param diagnosticLogsRetentionInDays int

@sys.description('Do not modify, used to set unique value for resource deployment.')
param time string = utcNow()

@sys.description('Sets purpose of the storage account.')
param storagePurpose string

@sys.description('ActiveDirectorySolution. ')
param ActiveDirectorySolution string = 'ActiveDirectoryDomainServices'

@sys.description('Sets location of DSC Agent.')
param dscAgentPackageLocation string

@sys.description('Custom OU path for storage.')
param storageCustomOuPath string

@sys.description('OU Storage Path')
param ouStgPath string

@sys.description('If OU for Azure Storage needs to be created - set to true and ensure the domain join credentials have priviledge to create OU and create computer objects or join to domain.')
param createOuForStorageString string

@sys.description('Managed Identity Client ID')
param managedIdentityClientId string

@sys.description('Kerberos Encryption. Default is AES256.')
param KerberosEncryption string 

@sys.description('Location of script. Default is located in workload/scripts')
param _artifactsLocation string = 'https://github.com/moisesjgomez/avdaccelerator/tree/ntfs-permissions/workload/scripts/'

@description('SAS Token to access script.')
param _artifactsLocationSasToken string = ''

param securityPrincipalNames string 

param storageSolution string 

param storageCount int = 1

param storageIndex int = 0

param netBios string = ''

// =========== //
// Variable declaration //
// =========== //

var varAzureCloudName = environment().name
var varStoragePurposeLower = toLower(storagePurpose)
var varAvdFileShareLogsDiagnostic = [
    'allLogs'
]
var varAvdFileShareMetricsDiagnostic = [
    'Transaction'
]

var varWrklStoragePrivateEndpointName = 'pe-${storageAccountName}-file'
var vardirectoryServiceOptions = (identityServiceProvider == 'AADDS') ? 'AADDS': (identityServiceProvider == 'AAD') ? 'AADKERB': 'None'
//var varStorageToDomainScriptArgs = '-DscPath ${dscAgentPackageLocation} -StorageAccountName ${storageAccountName} -StorageAccountRG ${storageObjectsRgName} -StoragePurpose ${storagePurpose} -DomainName ${identityDomainName} -IdentityServiceProvider ${identityServiceProvider} -AzureCloudEnvironment ${varAzureCloudName} -SubscriptionId ${workloadSubsId} -DomainAdminUserName ${domainJoinUserName} -CustomOuPath ${storageCustomOuPath} -OUName ${ouStgPath} -CreateNewOU ${createOuForStorageString} -ShareName ${fileShareName} -ClientId ${managedIdentityClientId}'
// =========== //
// Deployments //
// =========== //

// Call on the KV.
resource avdWrklKeyVaultget 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
    name: wrklKvName
    scope: resourceGroup('${workloadSubsId}', '${serviceObjectsRgName}')
}

// Provision the storage account and Azure Files.
module storageAndFile '../../../../carml/1.3.0/Microsoft.Storage/storageAccounts/deploy.bicep' = {
    scope: resourceGroup('${workloadSubsId}', '${storageObjectsRgName}')
    name: 'Storage-${storagePurpose}-${time}'
    params: {
        name: storageAccountName
        location: sessionHostLocation
        skuName: storageSku
        allowBlobPublicAccess: false
        publicNetworkAccess: deployPrivateEndpoint ? 'Disabled' : 'Enabled'
        kind: ((storageSku =~ 'Premium_LRS') || (storageSku =~ 'Premium_ZRS')) ? 'FileStorage' : 'StorageV2'
        azureFilesIdentityBasedAuthentication: {
            directoryServiceOptions: vardirectoryServiceOptions
            activeDirectoryProperties: (identityServiceProvider == 'AAD') ? {
                domainGuid: identityDomainGuid
                domainName: identityDomainName
            }: {}
        }
        accessTier: 'Hot'
        networkAcls: deployPrivateEndpoint ? {
            bypass: 'AzureServices'
            defaultAction: 'Deny'
            virtualNetworkRules: []
            ipRules: []
        } : {}
        fileServices: {
            shares: [
                {
                    name: fileShareName
                    shareQuota: fileShareQuotaSize * 100 //Portal UI steps scale
                }
            ]
            protocolSettings: fileShareMultichannel ? {
                smb: {
                    multichannel: {
                        enabled: fileShareMultichannel
                    }
                }
            } : {}
            diagnosticWorkspaceId: alaWorkspaceResourceId
            diagnosticLogCategoriesToEnable: varAvdFileShareLogsDiagnostic
            diagnosticMetricsToEnable: varAvdFileShareMetricsDiagnostic
        }
        privateEndpoints: deployPrivateEndpoint ? [
            {
                name: varWrklStoragePrivateEndpointName
                subnetResourceId: privateEndpointSubnetId
                customNetworkInterfaceName: 'nic-01-${varWrklStoragePrivateEndpointName}'
                service: 'file'
                privateDnsZoneGroup: {
                    privateDNSResourceIds: [
                        vnetPrivateDnsZoneFilesId
                    ]                    
                }
            }
        ] : []
        tags: tags
        diagnosticWorkspaceId: alaWorkspaceResourceId
        diagnosticLogsRetentionInDays: diagnosticLogsRetentionInDays
    }
}

// Call on the VM.
//resource managementVMget 'Microsoft.Compute/virtualMachines@2022-11-01' existing = {
//    name: managementVmName
//    scope: resourceGroup('${workloadSubsId}', '${serviceObjectsRgName}')
//}

// Custom Extension call in on the DSC script to join Azure storage account to domain. 
/*
module addShareToDomainScript './.bicep/azureFilesDomainJoin.bicep' = {
    scope: resourceGroup('${workloadSubsId}', '${serviceObjectsRgName}')
    name: 'Add-${storagePurpose}-Storage-Setup-${time}'
    params: {
        location: sessionHostLocation
        name: managementVmName
        file: storageToDomainScript
        scriptArguments: varStorageToDomainScriptArgs
        domainJoinUserPassword: avdWrklKeyVaultget.getSecret('domainJoinUserPassword')
        baseScriptUri: storageToDomainScriptUri
    }
    dependsOn: [
        storageAndFile
    ]
}
*/
/*
module ntfsPermissions 'ntfsPermissions.bicep' = if (contains(identityServiceProvider, 'ADDS')) {
    name: 'FslogixNtfsPermissions_${time}'
    scope: resourceGroup(workloadSubsId, serviceObjectsRgName)
    params: {
      _artifactsLocation: _artifactsLocation
      _artifactsLocationSasToken: _artifactsLocationSasToken
      CommandToExecute: 'powershell -ExecutionPolicy Unrestricted -File Set-NtfsPermissions.ps1 -ClientId ${managedIdentityClientId} -DomainJoinPassword "${domainJoinUserPassword}" -DomainJoinUserPrincipalName ${domainJoinUserName} -ActiveDirectorySolution "${ActiveDirectorySolution}" -Environment ${environment().name} -KerberosEncryptionType ${KerberosEncryption} -StorageAccountFullName ${storageAccountName} -FileShareName "${fileShareName}" -Netbios ${netBios} -OuPath "${ouStgPath}" -SecurityPrincipalNames "${securityPrincipalNames}" -StorageAccountResourceGroupName ${storageObjectsRgName} -StorageCount ${storageCount} -StorageIndex ${storageIndex} -StorageSolution ${storageSolution} -StorageSuffix ${environment().suffixes.storage} -SubscriptionId ${subscription().subscriptionId} -TenantId ${subscription().tenantId}'
      Location: sessionHostLocation
      ManagementVmName: managementVmName
      Timestamp: time
    }
    //...
  }
*/

module ntfsPermissions 'ntfsPermissions.bicep' = if (contains(identityServiceProvider, 'ADDS')) {
    name: 'FslogixNtfsPermissions_${time}'
    scope: resourceGroup(workloadSubsId, serviceObjectsRgName)
    params: {
      _artifactsLocation: _artifactsLocation
      _artifactsLocationSasToken: _artifactsLocationSasToken
      CommandToExecute: 'powershell -ExecutionPolicy Unrestricted -File Set-NtfsPermissions.ps1 -ClientId "2e21756f-35e3-42f5-b7a5-60154837dc03" -DomainJoinPassword "Admin1234567890!" -DomainJoinUserPrincipalName "admin01@mngenvmcap885230.onmicrosoft.com" -ActiveDirectorySolution "ActiveDirectoryDomainServices" -Environment "AzureCloud" -FslogixSolution "ProfileContainer" -KerberosEncryptionType "AES256" -StorageAccountFullName "stfslnf59d7br" -Netbios "mngenvmcap88523" -OuPath "OU=AVD,OU=Azure,DC=mngenvmcap885230,DC=onmicrosoft,DC=com" -SecurityPrincipalNames "AVD Users" -StorageAccountPrefix "stfslnf59d7br" -StorageAccountResourceGroupName "rg-avd-nf59-dev-use-storage" -StorageCount 1 -StorageIndex 1 -StorageSolution "AzureStorageAccount" -StorageSuffix "core.windows.net" -SubscriptionId "f6d0875c-f868-4019-94d2-bd7c10b761c8" -TenantId "2a3287e8-8fd5-4965-8a7d-2efacfbde54e"'
      Location: sessionHostLocation
      ManagementVmName: managementVmName
      Timestamp: time
    }
    //...
  }

/*
module ntfsPermissions 'ntfsPermissions.bicep' = if (contains(identityServiceProvider, 'ADDS')) {
  name: 'FslogixNtfsPermissions_${time}'
  scope: resourceGroup('${workloadSubsId}', '${serviceObjectsRgName}')
  params: {
    _artifactsLocation: _artifactsLocation //storageToDomainScriptUri
    _artifactsLocationSasToken: _artifactsLocationSasToken
    CommandToExecute: 'powershell -ExecutionPolicy Unrestricted -File Set-NtfsPermissions.ps1 -ClientId ${managedIdentityClientId} -DomainJoinPassword "${domainJoinUserPassword}" -DomainJoinUserPrincipalName ${domainJoinUserName} -ActiveDirectorySolution "${ActiveDirectorySolution}" -Environment ${environment().name} -FslogixSolution ${FslogixSolution} -KerberosEncryptionType ${KerberosEncryption} -StorageAccountName ${storageAccountName} -Netbios ${identityDomainName} -OuPath "${storageCustomOuPath}" -SecurityPrincipalNames "${SecurityPrincipalNames}" -StorageAccountPrefix ${StorageAccountPrefix} -StorageAccountResourceGroupName ${storageObjectsRgName} -StorageCount ${storageCount} -StorageIndex ${storageIndex} -StorageSolution ${storageSolution} -StorageSuffix ${environment().suffixes.storage} -SubscriptionId ${subscription().subscriptionId} -TenantId ${subscription().tenantId}' //change active directory solution to id service provider
    //DeploymentScriptNamePrefix: DeploymentScriptNamePrefix
    Location: sessionHostLocation
    ManagementVmName: managementVmName
    //TagsDeploymentScripts: TagsDeploymentScripts
    //TagsVirtualMachines: TagsVirtualMachines
    Timestamp: time
    //UserAssignedIdentityResourceId: UserAssignedIdentityResourceId
  }
  
  dependsOn: [
    privateDnsZoneGroups
    privateEndpoints
    shares
  ]
  
}*/


// =========== //
//   Outputs   //
// =========== //
