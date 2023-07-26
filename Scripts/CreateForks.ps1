$Subs = @(Get-AzSubscription).Id

$Subs.foreach(
{
    $Sentinel = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "True"}) | Select-Object -Property Name, ResourceGroupName

    $WorkspaceName = $Sentinel.Name

    $ResourceGroup = $Sentinel.ResourceGroupName

    $AnalyticalRules = @((Get-AzSentinelAlertRule -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName).Name)

    foreach($rule in $AnalyticalRules){
        New-Item -ItemType Directory $WorkspaceName
        $currentRule = Get-AzSentinelAlertRule -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName -RuleId $rule
        $filename = $currentRule.DisplayName -replace '[\\/:*?"<>|]', '_'
        $currentRule.Query| Out-File -FilePath $WorkspaceName "$filename.kql"
    }
})
