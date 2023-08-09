$ExtensionName = 'MicrosoftMonitoringAgent'
$GroupWorkspace = Read-Host -Prompt 'Enter the resource group where the customers existing workspaces is located'
$WorkspaceSub = Read-Host -Prompt 'Enter the subscription ID where the customers existing workspaces is located'
Set-AzContext -Subscription $WorkspaceSub
$WorkspaceNameCust = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $GroupWorkspace).Name
#Grabs the Workspace name from the customers existing subscription
$WorkspaceKeyCust = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $GroupWorkspace -Name $WorkspaceName
#Switch context back to the sub that we are working in aka our Ntirety sub.
$WorkingSub = Read-Host 'Enter the Sub where our new workspace is exist'
Set-AzContext -Subscription $WorkingSub
$WorkspaceName = (Get-AzOperationalInsightsWorkspace).Name
$WorkspaceKey = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $GroupWorkspace -Name $WorkspaceName
$ResourceGroups = (Get-AzVm).ResourceGroupName | Sort-Object -Unique

#Setup our hashtable values for use in the Set-AzVMExtension portion
$PublicSettingString = @{
    'workspaceId' = @($WorkspaceNameCust, $WorkspaceName )
}

$ProtectedSettingString = @{
    $WorkspaceCust = @{
        'workspaceKey' = $WorkspaceKeyCust.PrimarySharedKey
    }
    $WorkspaceUs = @{
        'workspaceKey' = $WorkspaceKey.PrimarySharedKey
    }
}

foreach($ResourceGroup in $ResourceGroups){
    $VmName = (Get-AzVM -ResourceGroupName $ResourceGroup)
    
    if($VmName.OsName -contains 'windows'){
    #Need to include multiple workspaces and keys in the below command
    
    Set-AzVMExtension -ResourceGroupName $ResourceGroup -Location $VmLocation -VMName $VmName -Name $ExtensionName -Publisher Microsoft.Azure.Monitoring.MonitoringAgent -ExtensionType $ExtensionName -TypeHandlerVersion 1.0 -SettingString '{"workspaceId":"<WorkspaceID>"}' -ProtectedSettingString '{"workspaceKey":"<WorkspaceKey>"}'
    }
    elseif($VmName.OsName -contains 'linux'){
    

    }
    #In case of the need to loop through the resource group
    #$AppendVariable = $ResourceGroup + 'VMs'
    #New-Variable -Name $AppendVariable -Value (Get-AzVM -ResourceGroupName $ResourceGroup).Name -Force
    #Write-Host $AppendVariable

}