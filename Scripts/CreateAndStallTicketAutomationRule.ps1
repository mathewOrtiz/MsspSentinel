#This script is used to manage the automation rule called CreateAndStallTicket.
#The rule will run the CreateRightnowTicket logic app and then close out the incident
#for the specified list of analytical rules based on the CSV file.

#CSV containing the rule names that we want to automate
$RuleNameCSV = "https://raw.githubusercontent.com/mathewOrtiz/MsspSentinel/FinalTesting/ConfigFiles/RulesToAutomate.csv"

#Function to get the rule URIs since they are specific to the subscription
function GetRuleURIs{
	param(
		[Parameter (Mandatory = $true)]
        [string]
        $RulesCsvPath,
		
		[Parameter (Mandatory = $true)]
        [string]
        $ResourceGroup,
		
		[Parameter (Mandatory = $true)]
        [string]
        $WorkspaceName
	)
	
	$RuleUris = @()
	
	#Download list of rules to automate from Github, import it and then delete it for cleanup.
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $RuleNameCSV -Outfile ".\RulesToAutomate.csv"
    $RulesForAutomation = Import-CSV -Path ".\RulesToAutomate.csv"
    Remove-Item -Path ".\RulesToAutomate.csv"
    $ProgressPreference = 'Continue'
	
	Write-Host ""
	#Loop through all new rule names
	$RulesForAutomation.ForEach({
		#Get current new rule name from table
		$RuleName = $_.DisplayName
		
		Write-Host "Searching for rule name " -NoNewLine
		Write-Host $RuleName -ForegroundColor cyan
		
		#Find the rule in workspace and pull the ID and display name (Name = ID)
		$Rule = (Get-AzSentinelAlertRule -ResourceGroupName $ResourceGroup -workspaceName $WorkspaceName | Where-Object {$_.DisplayName -eq $RuleName -and $_.enabled -eq "True"}) | Select-Object -Property Name, DisplayName, Id
		
		#If the rule is found add it to the array
		if($null -ne $Rule){
			Write-Host "`tRule found! Added for automation." -ForegroundColor yellow
			$RuleUris += $Rule.Id
		}
		else{
			#When rule is not found
			Write-Host "`tRule doesn't exist or it is disabled in this workspace." -ForegroundColor yellow
		}
	})
	
	Return $RuleUris
}

#Get list of subscription IDs for deployment
function GatherInfo{
	param(
		[Parameter (Mandatory = $true)]
        [string]
        $AllCustomers
	)
	
	if($AllCustomers -eq "all"){
		$Subscriptions = @(Get-AzSubscription -WarningAction Ignore).Id
	}
	elseif($AllCustomers -eq "multiple"){
		Write-Host "Enter a comma separated list of subscription IDs to deploy the automation rule: " -Foregroundcolor cyan -NoNewline
		$Subs = Read-Host
		
		$Subscriptions = @($Subs -split ",")
	}
	else{
		do{
			Write-Host "Enter the subscription ID to deploy the automation rule: " -Foregroundcolor cyan -NoNewline
			$Sub = Read-Host
		}
		while($Sub -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')
		
		$Subscriptions = @($Sub)
	}
	
	return $Subscriptions
}

#Deploy automation rule changes
function AutomationRule{
	param(
		[Parameter (Mandatory = $true)]
        [string]
        $Action,
		
		[Parameter (Mandatory = $true)]
        [array]
        $Subscriptions
	)
	
	#Build all the fields needed for the automation rule
	$AutomationRuleName = "CreateAndStallTicket"
	$AutomationRuleGuid = "CreateAndStallTicketGuid"
	$LogicAppResourceId = Get-AzLogicApp -ResourceGroupName "ntiretymsspprodsentinelresourcegroup" -Name "GenerateRightnowTicket"
	$AutomationRuleActionPlaybook = [Microsoft.Azure.PowerShell.Cmdlets.SecurityInsights.Models.Api20210901Preview.AutomationRuleRunPlaybookAction]::new()
	$AutomationRuleActionPlaybook.Order = 1
	$AutomationRuleActionPlaybook.ActionType = "RunPlaybook"
	$AutomationRuleActionPlaybook.ActionConfigurationLogicAppResourceId = ($LogicAppResourceId.Id)
	$AutomationRuleActionPlaybook.ActionConfigurationTenantId = (Get-AzContext).Tenant.Id
	$AutomationRuleActionIncident = [Microsoft.Azure.PowerShell.Cmdlets.SecurityInsights.Models.Api20210901Preview.AutomationRuleModifyPropertiesAction]::new()
	$AutomationRuleActionIncident.Order = 2
	$AutomationRuleActionIncident.ActionType = "ModifyProperties"
	$AutomationRuleActionIncident.ActionConfigurationStatus = "Closed"
	$AutomationRuleActionIncident.ActionConfigurationClassification = "Undetermined"
	$AutomationRuleActionIncident.ActionConfigurationClassificationComment = "Closed by ticket automation"
	$AutomationRuleActions = @($AutomationRuleActionPlaybook, $AutomationRuleActionIncident)
	$TriggeringLogicCondition = [Microsoft.Azure.PowerShell.Cmdlets.SecurityInsights.Models.Api20210901Preview.AutomationRulePropertyValuesCondition]::new()
	$TriggeringLogicCondition.ConditionPropertyName = "IncidentRelatedAnalyticRuleIds"
	$TriggeringLogicCondition.ConditionPropertyOperator = "Contains"
	
	foreach($Subscription in $Subscriptions){
		#Set subscription context
		$Context = Set-AzContext -Subscription $Subscription -WarningAction Ignore
		
		Write-Host "Starting work for " -NoNewline
		Write-Host $Context.Subscription.Name "-" $Context.Subscription.Id -ForegroundColor magenta
		
		#Get resource group and workspace if prod tag is ture
		$Sentinel = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "True"}) | Select-Object -Property Name, ResourceGroupName
		
		#This is for the Ntirety workspace since we have two. Ignore the InternalXDR worksapce.
		if($Sentinel.count -gt 1){
			$Sentinel = $Sentinel | Where-Object {$_.Name -like "*LogAnalyticsWorkspace"}
		}
		
		$WorkspaceName = $Sentinel.Name
		$ResourceGroup = $Sentinel.ResourceGroupName

		#Proceed if a prod workspace has been found
		if($null -ne $ResourceGroup -and $null -ne $WorkspaceName){
			#Create automation rule in disabled state
			if($Action -eq "Create"){
				$RulesToAutomate = GetRuleURIs -RulesCsvPath $RuleNameCSV -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName
				$TriggeringLogicCondition.ConditionPropertyValue = $RulesToAutomate
				
				Write-Host "`nCreating new automation rule " -NoNewLine
				Write-Host $AutomationRuleName -ForegroundColor green
				
				$temp = Update-AzSentinelAutomationRule -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $AutomationRuleGuid -DisplayName $AutomationRuleName -Order 1 -Action $AutomationRuleActions -TriggeringLogicCondition $TriggeringLogicCondition
			}
			#Enable the automation rule
			elseif($Action -eq "Enable"){
				$RulesToAutomate = GetRuleURIs -RulesCsvPath $RuleNameCSV -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName
				$TriggeringLogicCondition.ConditionPropertyValue = $RulesToAutomate
				
				Write-Host "`nEnabling automation rule " -NoNewLine
				Write-Host $AutomationRuleName -ForegroundColor green
				
				$temp = Update-AzSentinelAutomationRule -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $AutomationRuleGuid -DisplayName $AutomationRuleName -Order 1 -Action $AutomationRuleActions -TriggeringLogicCondition $TriggeringLogicCondition -TriggeringLogicIsEnabled
			}
			#Remove the automation rule
			elseif($Action -eq "Remove"){
				Write-Host "`nRemoving automation rule " -NoNewLine
				Write-Host $AutomationRuleName -ForegroundColor green
				
				$temp = Remove-AzSentinelAutomationRule -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $AutomationRuleGuid
			}
			else{
				Write-Host "`nNot a valid action. Please use Create, Enable or Remove."
			}
		}
		else{
			#When prod workspace is not found
			Write-Host "`nNo production workspace found for this customer." -ForegroundColor yellow
		}
	}
}

#Main menu - how many customers?
function MainMenu {
    $mainMenu = 'X'

    while($mainMenu -notin 'q', 'Q'){
        Write-Host "`n-------------------------------------------------"
        Write-Host -ForegroundColor Cyan "     Create and Stall Ticket Automation Rule"
        Write-Host "-------------------------------------------------"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " One Customer"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Multiple Customers"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " All Customers"
        Write-Host "`n-------------------------------------------------"
        $mainMenu = Read-Host "`nSelection (q to quit)"
		
		Clear-Host
        #Option 1 - One customer
        if($mainMenu -eq 1){
			$Subscriptions = GatherInfo -AllCustomers "one"
            SubMenu
        }
		#Option 2 - Multiple customers
        if($mainMenu -eq 2){
			$Subscriptions = GatherInfo -AllCustomers "multiple"
            SubMenu
        }
        #Option 3 - All customers
        if($mainMenu -eq 3){
			do{
				Write-Host "`nYou selected all custoemrs. Confirm to proceed (y/n)? " -NoNewline -ForegroundColor cyan
				$confirm = Read-Host
			}
			while($confirm -ne 'y' -and $confirm -ne 'n')
			
			if($confirm -eq 'y'){
				$Subscriptions = GatherInfo -AllCustomers "all"
				SubMenu
			}
        }
    }
}

#Sub menu - create, enable or remove automation rule
function SubMenu{
    $subMenu = 'X'
    while($subMenu -notin 'q', 'Q'){
        Clear-Host
        Write-Host "`n`t`t One Customer`n"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Create new automation rule"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Enable automation rule"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Delete/Disable automation rule"
		
        $subMenu = Read-Host "`nSelection (q to return to main menu)"

        #Option 1 - Create
        if($subMenu -eq 1){
            AutomationRule -Action Create -Subscriptions $Subscriptions
            #Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "Script execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
        #Option 2 - Enable
        if($subMenu -eq 2){
			AutomationRule -Action Enable -Subscriptions $Subscriptions
            #Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "Script execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		#Option 3 - Remove
        if($subMenu -eq 3){
			AutomationRule -Action Remove -Subscriptions $Subscriptions
            #Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "Script execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
    }
}

MainMenu