#This script deploys an analytical rule json file to ALL customers. 
#This can be one rule or multiple rules as long as it is all in one file.

#Connect to our main tenant
Connect-AzAccount -TenantId "984cdaad-80ea-4659-a39b-0a3b3f0c7bfb" -WarningAction Ignore

#Counter to workspaces that we deploy to
$count = 0

#Get list of subscriptions
$Subscriptions = @(Get-AzSubscription -WarningAction Ignore).Id

#Read in template file from command line argument
$TemplateFile = $args[0]

#Read in template file if none was provided as command line argument
if ($TemplateFile -eq $null) {
    $TemplateFile = Read-Host "File of Rule to Import (JSON)"
}

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
		$ResourceGroup = (Get-AzResourceGroup).ResourceGroupName | where {$_ -like "H*AzureSentinel"}
		$WorkspaceName = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "True"}).Name
	}
	
	#Deploy rule to workspace
    if($ResourceGroup -ne $null -and $WorkspaceName -ne $null) {

        Write-Host "Creating rule for " -NoNewline
        Write-Host "$WorkspaceName" -NoNewline -ForegroundColor cyan
        Write-Host " from template " -NoNewline
        Write-Host "$TemplateFile" -ForegroundColor green
        Write-Host ""

		$results = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $TemplateFile -Workspace $WorkspaceName
		$count = $count + 1
    }
}

Write-Host "Rule deployment to $count workspaces complete!" -ForegroundColor yellow