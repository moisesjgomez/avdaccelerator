param _artifactsLocation string
@secure()
param _artifactsLocationSasToken string
@secure()
param CommandToExecute string
//param DeploymentScriptNamePrefix string
param Location string
param ManagementVmName string
//param TagsDeploymentScripts object
//param TagsVirtualMachines object
param Timestamp string
//param UserAssignedIdentityResourceId string

resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = {
  name: '${ManagementVmName}/CustomScriptExtension'
  location: Location
  //tags: TagsVirtualMachines
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        '${_artifactsLocation}Set-NtfsPermissions.ps1${_artifactsLocationSasToken}'
      ]
      timestamp: Timestamp
    }
    protectedSettings: {
      commandToExecute: CommandToExecute
    }
  }
}
/*
module deploymentScript '../deploymentScript.bicep' = {
  name: 'DeploymentScript_FSLogix-CleanUp_${Timestamp}'
  params: {
    Arguments: '-VirtualMachineName ${ManagementVmName} -ResourceGroupName ${resourceGroup().name}'
    Location: Location
    Name: '${DeploymentScriptNamePrefix}fslogix'
    Script: 'param([string]$ResourceGroupName,[string]$VirtualMachineName); Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName -ForceDeletion $true -Force; $DeploymentScriptOutputs = @{}; $DeploymentScriptOutputs["virtualMachineName"] = $VirtualMachineName'
    Tags: TagsDeploymentScripts
    Timestamp: Timestamp
    UserAssignedIdentityResourceId: UserAssignedIdentityResourceId
  }
  dependsOn: [
    customScriptExtension
  ]
}
*/
