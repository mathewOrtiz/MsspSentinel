#Build all the fields needed for the automation rule
#$AutomationRuleName = "CreateAndStallTicket"
#$AutomationRuleGuid = "CreateAndStallTicketGuid"
$AutomationRuleName = "CreateTicket"
$AutomationRuleGuid = "CreateTicketGuid"
$LogicAppResourceId = Get-AzLogicApp -ResourceGroupName "ntiretymsspprodsentinelresourcegroup" -Name "TicketAutomationCreate"
$AutomationRuleActionPlaybook = [Microsoft.Azure.PowerShell.Cmdlets.SecurityInsights.Models.Api20210901Preview.AutomationRuleRunPlaybookAction]::new()
$AutomationRuleActionPlaybook.Order = 1
$AutomationRuleActionPlaybook.ActionType = "RunPlaybook"
$AutomationRuleActionPlaybook.ActionConfigurationLogicAppResourceId = ($LogicAppResourceId.Id)
$AutomationRuleActionPlaybook.ActionConfigurationTenantId = (Get-AzContext).Tenant.Id
#The closure piece is no longer handled by the automation rule. This is now done by the logic app.
$$AutomationRuleActionIncident = [Microsoft.Azure.PowerShell.Cmdlets.SecurityInsights.Models.Api20210901Preview.AutomationRuleModifyPropertiesAction]::new()
#$AutomationRuleActionIncident.Order = 2
#$AutomationRuleActionIncident.ActionType = "ModifyProperties"
#$AutomationRuleActionIncident.ActionConfigurationStatus = "Closed"
#$AutomationRuleActionIncident.ActionConfigurationClassification = "Undetermined"
#$AutomationRuleActionIncident.ActionConfigurationClassificationComment = "Closed by ticket automation"
#$AutomationRuleActions = @($AutomationRuleActionPlaybook, $AutomationRuleActionIncident)
$AutomationRuleActions = @($AutomationRuleActionPlaybook)
#$TriggeringLogicCondition = [Microsoft.Azure.PowerShell.Cmdlets.SecurityInsights.Models.Api20210901Preview.AutomationRulePropertyValuesCondition]::new()
#$TriggeringLogicCondition.ConditionPropertyName = "IncidentRelatedAnalyticRuleIds"
#$TriggeringLogicCondition.ConditionPropertyOperator = "Contains"

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
	
	#We create the storage context which will use our Azure AD credentials to authenticate to the Blob in order to auth to our files
	$StorageAccount = "scriptsentinel"
	$StorageContainer = "ticketautomation"
    $StorageAccAuth = New-AzStorageContext -StorageAccountName $StorageAccount
	$DirectoryName = "/home/Sentinel" + (Get-Date -Format "MMddyyyyHHmm")
    $FilePath = New-Item -ItemType Directory $DirectoryName
    $CsvFileName = (Get-AzStorageBlob -Context $StorageAccAuth -Container $StorageContainer).Name
	$RuleNameCSV = Get-AzStorageBlobContent -Context $StorageAccAuth -Blob $CsvFileName -Container $StorageContainer -Destination $FilePath
	$FullFilePath = $FilePath.FullName + '\' + $CsvFileName
	
	#Read in CSV of all the new rule names
	$RulesForAutomation = Import-Csv -Path $FullFilePath
	
	Remove-Item -Recurse -Path $FilePath
	
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
			$RuleUris += $Rule.Id
		}
		else{
			#When rule is not found
			Write-Host "Rule doesn't exist or it is disabled in this workspace." -ForegroundColor yellow
		}
	})
	
	Return $RuleUris
}

function GatherInfo{
	param(
		[Parameter (Mandatory = $true)]
        [string]
        $AllCustomers
	)
	
	if($AllCustomers -eq "all"){
		$Subscriptions = @(Get-AzSubscription -WarningAction Ignore).Id
		#Write-Host $Subscriptions
	}
	elseif($AllCustomers -eq "multiple"){
		Write-Host "Enter a comma separated list of subscription IDs to deploy the automation rule: " -Foregroundcolor cyan -NoNewline
		$Sub = Read-Host
		
		$Subscriptions = @($Sub -split ",")
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

function AutomationRule{
	param(
		[Parameter (Mandatory = $true)]
        [string]
        $Action,
		
		[Parameter (Mandatory = $true)]
        [array]
        $Subscriptions
	)
	
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
			if($Action -eq "Create"){
				#$RulesToAutomate = GetRuleURIs -RulesCsvPath $RuleNameCSV -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName
				#$TriggeringLogicCondition.ConditionPropertyValue = $RulesToAutomate
				
				Write-Host "`nCreating new automation rule " -NoNewLine
				Write-Host $AutomationRuleName -ForegroundColor green
				
				$temp = Update-AzSentinelAutomationRule -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $AutomationRuleGuid -DisplayName $AutomationRuleName -Order 1 -Action $AutomationRuleActions -TriggeringLogicIsEnabled
				#-TriggeringLogicCondition $TriggeringLogicCondition
			}
			elseif($Action -eq "Enable"){
				#$RulesToAutomate = GetRuleURIs -RulesCsvPath $RuleNameCSV -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName
				#$TriggeringLogicCondition.ConditionPropertyValue = $RulesToAutomate
				
				Write-Host "`nEnabling automation rule " -NoNewLine
				Write-Host $AutomationRuleName -ForegroundColor green
				
				$temp = Update-AzSentinelAutomationRule -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $AutomationRuleGuid -DisplayName $AutomationRuleName -Order 1 -Action $AutomationRuleActions -TriggeringLogicIsEnabled
				#-TriggeringLogicCondition $TriggeringLogicCondition
			}
			elseif($Action -eq "Remove"){
				Write-Host "`nRemoving automation rule " -NoNewLine
				Write-Host $AutomationRuleName -ForegroundColor green
				
				$temp = Remove-AzSentinelAutomationRule -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Id $AutomationRuleGuid
			}
			else{
				Write-Host "Not a valid action. Please use Create, Enable or Remove."
			}
		}
		else{
			#When prod workspace is not found
			Write-Host "No production workspace found for this customer." -ForegroundColor yellow
		}
	}
}

function MainMenu {
    $mainMenu = 'X'

    while($mainMenu -notin 'q', 'Q'){
        Write-Host "`n-----------------------------"
        Write-Host -ForegroundColor Cyan "          Main Menu"
        Write-Host "-----------------------------"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Deploy or make changes to one customer"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Deploy or make changes to multiple customers"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Deploy or make changes to all customers"
        Write-Host "`n-----------------------------"
        $mainMenu = Read-Host "`nSelection (q to quit)"
        # Create Automation Rule in Disabled State
        if($mainMenu -eq 1){
            AutomateRuleOneCustomer
        }
		# Create Automation Rule in Disabled State
        if($mainMenu -eq 2){
            AutomateRuleMultipleCustomers
        }
        # Enable Automation Rule
        if($mainMenu -eq 3){
            AutomateRuleAllCustomers
        }
    }
}

function AutomateRuleOneCustomer {
    $subMenu2 = 'X'
    Clear-Host
    $Subscriptions = GatherInfo -AllCustomers "one"
    while($subMenu2 -notin 'q', 'Q'){
        Clear-Host
        Write-Host "`n`t`t One Customer`n"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Create new automation rule"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Enable automation rule"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Delete/Disable automation rule"
		
        $subMenu2 = Read-Host "`nSelection (q to return to main menu)"

        # Option 1
        if($subMenu2 -eq 1){
            AutomationRule -Action Create -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
        # Option 2
        if($subMenu2 -eq 2){
			AutomationRule -Action Enable -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 3
        if($subMenu2 -eq 3){
			AutomationRule -Action Remove -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
    }
}

function AutomateRuleMultipleCustomers {
    $subMenu2 = 'X'
    Clear-Host
    $Subscriptions = GatherInfo -AllCustomers "multiple"
    while($subMenu2 -notin 'q', 'Q'){
        Clear-Host
        Write-Host "`n`t`t One Customer`n"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Create new automation rule"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Enable automation rule"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Delete/Disable automation rule"
		
        $subMenu2 = Read-Host "`nSelection (q to return to main menu)"

        # Option 1
        if($subMenu2 -eq 1){
            AutomationRule -Action Create -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
        # Option 2
        if($subMenu2 -eq 2){
			AutomationRule -Action Enable -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 3
        if($subMenu2 -eq 3){
			AutomationRule -Action Remove -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
    }
}

function AutomateRuleAllCustomers {
    $subMenu2 = 'X'
    #Clear-Host
	$Subscriptions = GatherInfo  -AllCustomers "all"
    while($subMenu2 -notin 'q', 'Q'){
        #Clear-Host
        Write-Host "`n`t`t All Customers`n"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Create new automation rule"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Enable automation rule"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Delete/Disable automation rule"
		
        $subMenu2 = Read-Host "`nSelection (q to return to main menu)"

        # Option 1
        if($subMenu2 -eq 1){
            AutomationRule -Action Create -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
        # Option 2
        if($subMenu2 -eq 2){
			AutomationRule -Action Enable -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 3
        if($subMenu2 -eq 3){
			AutomationRule -Action Remove -Subscriptions $Subscriptions
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
    }
}

MainMenu