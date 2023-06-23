#This script deploys a rule and disables two other rules.
#This is meant to combine two rules into one.

$successCount = 0
$failedCount = 0

do{
    Write-Host "Enter our main tenant ID: " -Foregroundcolor Cyan -NoNewline
    $MainTenantId = Read-Host 
}
while($MainTenantId -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')

Write-Host "Enter the names of the two rule to disbale. Only include the main rule name do not include things like Azure Default or [AZURE-000]" -Foregroundcolor Cyan
Write-Host "Rule 1: " -Foregroundcolor Cyan -NoNewline
$Rule1ToDisable = Read-Host 

Write-Host "Rule 2: " -Foregroundcolor Cyan -NoNewline
$Rule2ToDisable = Read-Host 

#Read in template file from command line argument
$TemplateFile = $args[0]

#Read in template file if none was provided as command line argument
do {
    Write-Host "File of Rule to Import (JSON): " -Foregroundcolor Cyan -NoNewline
    $TemplateFile = Read-Host 
}
while($null -eq $TemplateFile)

#Connect to main Ntirety tenant
#Connect-AzAccount -TenantId $MainTenantId -WarningAction Ignore

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
        
        $RuleIdsToDisable = @((Get-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName | Where-Object {$_.DisplayName -like "*$Rule1ToDisable*" -or $_.DisplayName -like "*$Rule2ToDisable*"}).Name)
        $disabledCount = 0
        $failedDisableCount = 0

        #Use update rule to disable it
        $RuleIdsToDisable.ForEach({
            Write-Host "Disabling rule " -NoNewline
            Write-Host $_ -NoNewline -ForegroundColor red
            Write-Host " for " -NoNewline
            Write-Host $WorkspaceName -ForegroundColor cyan
            Write-Host ""

            $Error.Clear()
            $results = Update-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName -RuleId $_ -Disabled -Scheduled

            if(!$Error){
                $disabledCount = $disabledCount + 1
            }
            else {
                $failedDisableCount = $failedDisableCount + 1
            }
        })

        Write-Host "Rules successfully dsiabled: " -NoNewline -ForegroundColor Cyan
        Write-Host $disabledCount -ForegroundColor Green
        Write-Host "Rules failed to disable: " -NoNewline -ForegroundColor Cyan
        Write-Host $failedDisableCount -ForegroundColor Red

        #Deploy New Rule
        Write-Host "Creating rule for " -NoNewline
        Write-Host "$WorkspaceName" -NoNewline -ForegroundColor Cyan
        Write-Host " from template " -NoNewline
        Write-Host "$TemplateFile" -ForegroundColor Green
        Write-Host ""
    
        $Error.Clear()
        $results = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile -Workspace $WorkspaceName

        if(!$Error){
            $successCount = $successCount + 1
        }
        else {
            $failedCount = $failedCount + 1
        }
    }
}

Write-Host "Rule deployment to " -ForegroundColor Cyan -NoNewline
Write-Host $successCount -NoNewline
Write-Host " workspaces complete!" -ForegroundColor Cyan
Write-Host "Rule deployment failed to " -ForegroundColor Red -NoNewline
Write-Host $failedCount -NoNewline
Write-Host " workspaces." -ForegroundColor Red