#This script will rename all the rules in every customer workspace
#The new rules are pulled in from a CSV file that must be supplied

#Currently this file only has the Windows rules. Need to add the rest.
$RuleNameCSV = "C:\Users\mackermann\Sentinel\Rule Renaming\NewRuleNames.csv"

#Read in main tenant ID
do{
    Write-Host "Enter our main tenant ID: " -Foregroundcolor Cyan -NoNewline
    $MainTenantId = Read-Host 
}
while($MainTenantId -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')

#Connect to main Ntirety tenant
Connect-AzAccount -TenantId $MainTenantId -WarningAction Ignore

#Get list of subscriptions
$Subscriptions = @(Get-AzSubscription -WarningAction Ignore).Id

#Read in CSV of all the new rule names
$AllNewRuleNames = Import-Csv -Path $RuleNameCSV

#Loop through all subs
foreach($Subscription in $Subscriptions){
	#Set subscription context
	$Context = Set-AzContext -Subscription $Subscription -WarningAction Ignore
	
	Write-Host "Starting work for " -NoNewline
	Write-Host $Context.Subscription.Name "-" $Context.Subscription.Id -ForegroundColor cyan
	
	#Get resource group and workspace if prod tag is ture
	$Sentinel = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "True"}) | Select-Object -Property Name, ResourceGroupName
	$WorkspaceName = $Sentinel.Name
	$ResourceGroup = $Sentinel.ResourceGroupName

	#Proceed if a prod workspace has been found
	if($null -ne $ResourceGroup -and $null -ne $WorkspaceName){
		#Loop through all new rule names
		$AllNewRuleNames.ForEach({
			#Get current new rule name from table
			$NewRuleName = $_.DisplayName
			
			#Split the prefix off so we can search for the existing rule
			#Splits into two parts at the space between the prefix and rule name
			#i.e. [MS-060] Rare RDP Connections becomes index 0 = [MS-060] and index 1 = Rare RDP Connections
			$RuleNameNoPrefix = ($NewRuleName -split " ", 2)[1]
			
			Write-Host "`nSearching for rule name " -NoNewLine
			Write-Host $RuleNameNoPrefix -ForegroundColor cyan
			
			#Find the rule in workspace and pull the ID and display name (Name = ID)
			$RuleToUpdate = (Get-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName | Where-Object {$_.DisplayName -like "*$RuleNameNoPrefix*" -and $_.enabled -eq "True"}) | Select-Object -Property Name, DisplayName
			
			#If the rule is found do this stuff
			if($null -ne $RuleToUpdate){
				#Pull the ID and display name of the found rule into separate variables
				$RuleIdToUpdate = $RuleToUpdate.Name
				$RuleNameToUpdate = $RuleToUpdate.DisplayName
				
				#Check if the rule is already named properly
				if($RuleNameToUpdate -eq $NewRuleName){
					Write-Host "Rule already has correct name: " -NoNewLine -ForegroundColor green
					Write-Host $RuleNameToUpdate
				}
				else{
					#If its named incorrectly, rename it
					Write-Host "Old Rule Name: " -NoNewLine -ForegroundColor red
					Write-Host $RuleNameToUpdate
					Write-Host "New Rule Name: " -NoNewLine -ForegroundColor green
					Write-Host $NewRuleName
					
					#Uncomment out this line after testing is done
					#Update-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName -RuleId $RuleIdToUpdate -Scheduled -DisplayName $NewRuleName
				}
			}
			else{
				#When rule is not found
				Write-Host "Rule doesn't exist or it is disabled in this workspace." -ForegroundColor yellow
			}
		})
	}
	else{
		#When prod workspace is not found
		Write-Host "No production workspace found for this customer." -ForegroundColor yellow
	}
}