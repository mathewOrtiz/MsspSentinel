#This script disables a rule in all customer environments.

$successCount = 0
$failedCount = 0

do{
    Write-Host "Enter our main tenant ID: " -Foregroundcolor Cyan -NoNewline
    $MainTenantId = Read-Host 
}
while($MainTenantId -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')

Write-Host "Enter the names of the two rule to disbale. Only include the main rule name do not " -Foregroundcolor Cyan
Write-Host "include things like Azure Default or [AZURE-000]. Also no quotes needed." -Foregroundcolor Cyan
Write-Host "Rule Name: " -Foregroundcolor Cyan -NoNewline
$RuleNameToDisable = Read-Host 

#Connect to main Ntirety tenant
Connect-AzAccount -TenantId $MainTenantId -WarningAction Ignore

#Get list of subscriptions
$Subscriptions = @(Get-AzSubscription -WarningAction Ignore).Id

#Loop through all subcriptions
foreach($Subscription in $Subscriptions){
    $context = set-AzContext -Subscription $Subscription -WarningAction Ignore

    #Hard code resource group and workspace for subscriptions that don't follow our standard naming convention of H*AzureSentinel
	if($Subscription -eq "c8200cf1-f460-4b23-b162-ae7ec3b8f8bc"){
		#Bedrock
		$ResourceGroup = "svcPROD"
		$WorkspaceName = "BMC-LAW"
	}
	elseif($Subscription -eq "e5bd5c92-7984-4ce6-9c58-5a3c7e465f00"){
		#Ntirety
		$ResourceGroup = "NtiretyMsspProdSentinelResourceGroup"
		$WorkspaceName = "NtiretyMsspProdSentinelLogAnalyticsWorkspace"
	}
	elseif($Subscription -eq "7f7e5051-4818-4696-a006-b0c4420aab91"){
		#INS
		$ResourceGroup = "h228100-ntirety-sentinel"
		$WorkspaceName = "H228100"
	}
	else{
		#Grab resource group based on naming convention and then grab the workspace name if its tagged production = true
		$ResourceGroup = (Get-AzResourceGroup).ResourceGroupName | Where-Object {$_ -like "H*AzureSentinel"}
		$WorkspaceName = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "True"}).Name
	}

    if($null -ne $ResourceGroup -and $null -ne $WorkspaceName) {
        
        $RuleToDisable = (Get-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName | Where-Object {$_.DisplayName -like "*$RuleNameToDisable*"})

        if($null -ne $RuleToDisable)
        {
            $RuleId = $RuleToDisable.Name
            $RuleName = $RuleToDisable.DisplayName

            #Use update rule to disable it
            Write-Host "`nDisabling rule " -NoNewline -ForegroundColor cyan
            Write-Host $RuleName -NoNewline -ForegroundColor yellow
            Write-Host " for " -NoNewline -ForegroundColor cyan
            Write-Host $WorkspaceName -ForegroundColor green

            $Error.Clear()
            $results = Update-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName -RuleId $RuleId -Disabled -Scheduled

            if(!$Error){
                $successCount = $successCount + 1
                Write-Host "Rule ID successfully dsiabled: " -NoNewline -ForegroundColor Cyan
                Write-Host $RuleId -ForegroundColor Green
                
            }
            else {
                $failedCount = $failedCount + 1
                Write-Host "Rule ID failed to disable: " -NoNewline -ForegroundColor Cyan
                Write-Host $RuleId -ForegroundColor Red
            }
        }
        else {
            Write-Host "`nRule " -NoNewline -ForegroundColor cyan
            Write-Host $RuleNameToDisable -NoNewline -ForegroundColor yellow
            Write-Host " not found in " -NoNewline -ForegroundColor cyan
            Write-Host $WorkspaceName -NoNewline -ForegroundColor Magenta
            Write-Host ". Skipping." -ForegroundColor cyan
        }
    }
}

Write-Host "Rule disabled in " -ForegroundColor Cyan -NoNewline
Write-Host $successCount -NoNewline
Write-Host " workspaces!" -ForegroundColor Cyan
Write-Host "Rule failed to disable in " -ForegroundColor Red -NoNewline
Write-Host $failedCount -NoNewline
Write-Host " workspaces." -ForegroundColor Red