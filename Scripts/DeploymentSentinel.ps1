#Global Variable initialized
$ErrorActionPreference = 'silentlycontinue'
$ErrorView = 'CategoryView'
$DefaultColor = [ConsoleColor]::Cyan
$pattern = "^H\d+AzureSentinel$"
$RandNum = Get-Random -Maximum 10000
$BaseName = "Sentinel"
$DirectoryName = $BaseName += $RandNum
$FilePath = New-Item -ItemType Directory /home/$DirectoryName
$SocLevel1Id = (Get-AzADGroup -SearchString "SocLevel1").Id
$SocLevel2Id = (Get-AzADGroup -SearchString "SocLevel2").Id
$SocEngId = (Get-AzADGroup -SearchString "Security Engineering").Id
$SentinelReadersId = (Get-AzADGroup -SearchString "SentinelReaders").Id
$SentinelSecurityContrib = (Get-AzRoleDefinition -Name 'Microsoft Sentinel Contributor').Id
$ArcConnected = (Get-AzRoleDefinition -Name 'Azure Connected Machine Resource Administrator').Id
$MonitoringContrib = (Get-AzRoleDefinition -Name 'Monitoring Contributor').Id
$ResourcePolicyContrib = (Get-AzRoleDefinition -Name 'Resource Policy Contributor').Id
$ManagedIdContrib = (Get-AzRoleDefinition -Name 'Managed Identity Contributor').Id
$VirtualMachineContrib = (Get-AzRoleDefinition -Name 'Classic Virtual Machine Contributor').Id
$SentinelResponder = (Get-AzRoleDefinition -Name 'Microsoft Sentinel Responder').Id
$LogAnalyticsReader = (Get-AzRoleDefinition -Name 'Log Analytics Reader').Id
$TagContrib = (Get-AzRoleDefinition -Name 'Tag Contributor').Id
$SentinelReaderRole = (Get-AzRoleDefinition -Name 'Reader').Id
$DisplayNameEng = "Security Engineer"
$DisplayNameL1 = "SOC L1"
$DisplaynameL2 = "SOC L2"
$DisplayNameReaders = "SOC Readers"
$HomeContext = (Get-AzContext).Tenant.Id
$StorageAccountName = "scriptsentinel"
$FunctionsToCheck = @{}
$AzSubscription = ""
$location = ""

function GatherInfo{
    #$global:StorageAccountName = Read-Host "Enter the name of the storage account containing the analytical rules"

    #The following is used in order to configure the necessary context to the new customer subscription.
    do{
        Write-Host "Enter in the tenant ID of the subscription that you need to deploy the Sentinel resources for.
    
This can be retrieved from the Azure AD overview page. Customer Tenant ID: " -Foregroundcolor $DefaultColor -NoNewline
        $NewInstance = Read-Host 
    }
    while($NewInstance -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')
    $CustContext = Set-AzContext -Tenant $NewInstance

    do{
        Write-Host "Enter the subscription ID you would like to deploy the solution: " -Foregroundcolor $DefaultColor -NoNewline
        $NewSub = Read-Host
    }
    while($NewSub -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')

    #After setting our context to the necessary customer tenant we grab the Subscription ID to use later on for Analytical rule import.
    $global:AzSubscription = (Get-AzContext).Subscription.Id

    do{
        Write-Host "Enter the location to deploy (Options: eastus or westus): " -NoNewline -ForegroundColor $DefaultColor
        $global:location = Read-Host
    }
    while($global:location -notin "eastus", "westus")

    #Creating the static variables to use for housing errors for the error check portion of the scipt. This hashtable will have all of the necessary errors. 
    $global:FunctionsToCheck = @{}
    $error.Clear()
}

#Begin the functions 
function ResourceProviders{
    #The below needs to be populated With the necessary namespaces as well as creating a array with the required resource providers.
    $RequiredProviderCheck =  @('Microsoft.SecurityInsights', 'Microsoft.OperationalInsights','Microsoft.PolicyInsights','Microsoft.HybridConnectivity','Microsoft.ManagedIdentity','Microsoft.AzureArcData','Microsoft.OperationsManagement','microsoft.insights','Microsoft.HybridCompute','Microsoft.GuestConfiguration','Microsoft.Automanage','Microsoft.MarketplaceNotifications','Microsoft.ManagedServices')
    
    #The following loop will work through the subscription in order to register all of the resource providers we need for our resources. 
    foreach($Provider in $RequiredProviderCheck){
        $ProviderName = (Get-AzResourceProvider -ProviderNamespace $Provider).RegistrationState | Select-Object -First 1
        $ProviderName
        if($ProviderName -match "NotRegistered"){
            Register-AzResourceProvider -ProviderNamespace $Provider
        }
    }
}

#Function to create the necessary connection to our main tenant. 
function LightHouseConnection{
    $SocL1ObjectId = $SocLevel1Id
    $SocL2ObjectId = $SocLevel2Id
    $SocEngObjectId = $SocEngId
    $SentinelReaders = $SentinelReadersId
    $TenantId = $HomeContext
    #Creates our hashtable to utilize for the parameters for the JSON file.
    $parameters = [ordered]@{
        mspOfferName = @{
            value = "Ntirety Lighthouse SOC"
        }
        mspOfferDescription = @{
            value = "Ntirety SOC access granted"
        }
        managedByTenantId = @{
            value = $TenantId
        }
        authorizations =@{
            value =@(
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $SentinelSecurityContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $ArcConnected
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $MonitoringContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $TagContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $VirtualMachineContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $ResourcePolicyContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $ManagedIdContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocL1ObjectId
                    roleDefinitionId = $SentinelResponder
                    principalIdDisplayName = $DisplayNameL1
                }
                @{
                    principalId = $SocL2ObjectId
                    roleDefinitionId = $SentinelResponder
                    principalIdDisplayName = $DisplaynameL2
                }
                @{
                    principalId = $SocL1ObjectId
                    roleDefinitionId = $LogAnalyticsReader
                    principalIdDisplayName = $DisplayNameL1
                }
                @{
                    principalId = $SocL2ObjectId
                    roleDefinitionId = $LogAnalyticsReader
                    principalIdDisplayName = $DisplaynameL2
                }
                @{
                    principalId = $SentinelReaders
                    roleDefinitionId = $SentinelReaderRole
                    principalIdDisplayName = $DisplayNameReaders
                }  
            )
        }
    }
    #Define the resources for the parameter file using a hashtable. 
    $MainObject = [ordered]@{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
        contentVersion = "1.0.0.0"
        parameters = $parameters
    }

    #Converts the above to a JSON formatted file to be used for the ARM template push. 
    $MainObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $FilePath/TemplateParam.json

    Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/Azure-Lighthouse-samples/master/templates/delegated-resource-management/subscription/subscription.json -OutFile $FilePath/ArmTemplateDeploy.json 
    New-AzDeployment -TemplateFile $FilePath/ArmTemplateDeploy.json -TemplateParameterFile $FilePath/TemplateParam.json -Location $global:location
}

function DeploySentinel{
    #Once the above has completed we have ensured that the necessary providers for the rest of our task have been completed
    #in the below lines we setup our variables which will be used later. We enforce the checking by using a dynamic regex check

    $Tag = @{
        "Production" = "False"
    }

    do{
        Write-Host ""
        do{
             Write-Host "Please enter the customer H#: " -NoNewline -ForegroundColor $DefaultColor
             $CustName = Read-Host
        }
        while($CustName -notmatch '^H\d+$')
        
        $CustName += "AzureSentinel"

        Write-Host "`nConfirm the following..."
        Write-Host "Sentinel Workspace and Resource Group Name: " -NoNewline
        Write-Host $CustName -ForegroundColor Green
        Write-Host "Location: " -NoNewline
        Write-Host $global:location -ForegroundColor Green
        Write-Host "`nProceed (y/n): " -NoNewline -ForegroundColor $DefaultColor
        $confirm = Read-Host
    }
    while($confirm -ne 'y')

    #Deploys the resource group which will house the Sentinel resources. 
    New-AzResourceGroup -Name $CustName -Location $global:location

    #using the match regex we are able to ensure we grab only the resource group that we created in the previous step of variable init. 
    $ResourceGroupName = (Get-AzResourceGroup).ResourceGroupName

    New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $CustName -Location $global:location -Tag $Tag -Sku pergb2018

    #Deploy Sentinel
    New-AzSentinelOnboardingState -ResourceGroupName $CustName -WorkspaceName $CustName -Name "default"
}

function PolicyCreation{

    [CmdletBinding()]
    param (
        [Parameter(DontShow)]
        [String]
        $WinAssignName = 'WindowsOms',
    
        [Parameter(DontShow)]
        [String]
        $LinAssignName = 'LinuxOms',
    
        [Parameter(DontShow)]
        [String]
        $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Where-Object {$_ -match $pattern}),

        [Parameter(DontShow)]
        [string]
        $ActivityName = 'AzureActivityLog'
    )
    
    #Grabs our policy Definition for use in the next step. 
    $DefinitionWin = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Windows servers' }
    $DefinitionLinux = Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Linux servers. See deprecation notice below'}
    $DefinitionActivity = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Azure Activity logs to stream to specified Log Analytics workspace'}

    $WorkspaceName = (Get-AzOperationalInsightsWorkspace).Name
    
    #begin creation of our new policy
    
    #need to see if the variables being assigned here is really necessary. 
    New-AzPolicyAssignment -Name $WinAssignName -PolicyDefinition $DefinitionWin -PolicyParameterObject @{"logAnalytics"="$WorkspaceName"} -AssignIdentity -Location $global:location -WarningAction Ignore
    New-AzPolicyAssignment -Name $LinAssignName -PolicyDefinition $DefinitionLinux -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -Location $global:location -WarningAction Ignore
    New-AzPolicyAssignment -Name $ActivityName -PolicyDefinition $DefinitionActivity -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -Location $global:location -WarningAction Ignore
    #Now we need to fetch the policy -Id of the above. 
    
    $PolicyAssignWind = (Get-AzPolicyAssignment -Name $WinAssignName -WarningAction Ignore).PolicyAssignmentId
    $PolicyAssignLinux = (Get-AzPolicyAssignment -Name $LinAssignName -WarningAction Ignore).PolicyAssignmentId
    $PolicyAssignActivity = (Get-AzPolicyAssignment -Name $ActivityName -WarningAction Ignore).PolicyAssignmentId 
    
    Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignWind -Name WindowsOmsRemediation
    Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignLinux -Name LinuxOmsRemediation
    Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignActivity -Name AzureActivityLogRemediation    
}
    
#Sets our Table Retention 
function RetentionSet{
    [CmdletBinding()]
    param (
        [Parameter(DontShow)]
        [String]
        $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Where-Object {$_ -match $pattern}),
    
        [Parameter( DontShow)]
        [String]
        $ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Where-Object {$_ -match $pattern}),
    
        [Parameter(DontShow)]
        [array]
        $tables = @((Get-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName).Name)
    )
    #Before beginning iteration through the table we query to ensure that our Job has been completed to deploy our Sentinel resources. If this hasn't been completed then we wait for it to finish.
    #The below will re-run the sentinel deploy script in order to ensure that the necessary resources are created to be modified. 
    $tables.ForEach({Update-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -TableName $_ -RetentionInDays 90 -TotalRetentionInDays 365 -AsJob})  
}
    
function DataConnectors{
    [CmdletBinding()]
    param (
        [Parameter(DontShow)]
        [string]
        $ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Where-Object {$_ -match $pattern}),
    
        [Parameter(DontShow)]
        [string]
        $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Where-Object {$_ -match $pattern}),
    
        [Parameter(DontShow)]
        [array]
        $WinLogSources = @("System", "Application"),
    
        [Parameter(DontShow)]
        [array]
        $LinuxLogSources = @('Auth','authpriv','syslog','cron'),

        [Parameter(DontShow)]
        [string]
        $Uri = "https://raw.githubusercontent.com/mathewOrtiz/MsspSentinel/FinalTesting/ARM/NtiretySecurityWinEvents.json",

        [Parameter(DontShow)]
        [string]
        $SubscriptionId = ((Get-AzContext).Subscription.Id)
    )
    #Enables Common Security Event logs by pulling the template file we need from github & passing the parameters inline.
    Invoke-WebRequest -Uri $Uri -OutFile $FilePath/NtiretySecurityWinEvents.json
    New-AzResourceGroupDeployment -TemplateFile $FilePath/NtiretySecurityWinEvents.json -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroup -securityCollectionTier Recommended -AsJob
    
    #Deploys our other Win & Linux system logs.
    $WinLogSources.ForEach({New-AzOperationalInsightsWindowsEventDataSource -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Name $_ -CollectErrors -CollectWarnings -CollectInformation -EventLogName $_})
    $LinuxLogSources.ForEach({New-AzOperationalInsightsLinuxSyslogDataSource -Name $_ -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Facility $_ -CollectEmergency -CollectAlert -CollectCritical -CollectError -CollectWarning -CollectNotice})
}

#This function will need to be configured in order to get us our output that will 
function DeployAnalyticalRules {
    #The following below is used in order to set our context working directory back to our primary Sentinel tenant. We then reauth to the subscription under this AD user versus our Ntirety Principal User.
    Set-AzContext -Tenant $HomeContext
    Set-AzContext -Subscription $global:AzSubscription

    #We create the storage context which will use our Azure AD credentials to authenticate to the Blob in order to auth to our files
    $StorageAccAuth = (New-AzStorageContext -StorageAccountName $global:StorageAccountName)
    $ContainerName = ((Get-AzStorageContainer -Context $StorageAccAuth).Name)
    $AnalyticalRules = @((Get-AzStorageBlob -Context $StorageAccAuth -Container $ContainerName).Name)   
    $ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Where-Object {$_ -match $pattern})
    $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Where-Object {$_ -match $pattern})

    #The following will need download all of the files to our working directory. 
    $AnalyticalRules.foreach({
        Get-AzStorageBlobContent -Context $StorageAccAuth -Blob $_ -Container $ContainerName -Destination $FilePath
    })

    #Can use the raw JSON files in order to deploy the analytical rules the params that are needed are the workspace & potentially the region.
    $AnalyticalRules.ForEach({
        New-AzResourceGroupDeployment -Name $_ -ResourceGroupName $ResourceGroup -TemplateFile $FilePath/$_ -Workspace $WorkspaceName -AsJob
        Write-Output 'The Analytical Rule Set for '$_' is being deployed once this has completed the next one will deploy'
    })
}

function ErrorCheck{
    param(
        [Parameter (Mandatory = $true)]
        [string]
        $FunctionName
    )

    if($error -ne $null){
        $error.ForEach({
            $global:FunctionsToCheck.add($FunctionName, $_.Exception.Message)
        })
        $error.Clear()
    }

    Write-Host "The following functions of the deployment had errors: " 
    Write-Host $global:FunctionsToCheck.Keys -ForegroundColor Red
}

function MainMenu {
    $mainMenu = 'X'
    while($mainMenu -notin 'q', 'Q'){
        Clear-Host
        Write-Host "`n`t`t Sentinel Deployment Script`n"
        Write-Host -ForegroundColor Cyan "Main Menu"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " New Build"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Finish Existing Build"
        $mainMenu = Read-Host "`nSelection (q to quit)"
        # Launch New Build submenu
        if($mainMenu -eq 1){
            NewBuild
        }
        # Launch Exisiting Build submenu
        if($mainMenu -eq 2){
            ExistingBuild
        }
    }
}

function NewBuild {
    $subMenu1 = 'X'
    while($subMenu1 -notin 'q', 'Q', 'n', 'N'){
        Clear-Host
        GatherInfo
        Write-Host "`n`t`t New Build`n"
        Write-Host -ForegroundColor DarkCyan "Type YES to continue with new build (case-sensitive)"

        $subMenu1 = Read-Host "`nSelection (q to return to main menu)"

        # Continue
        if($subMenu1 -ceq 'YES'){
			Clear-Host
            Write-Host "`nDeploying Sentinel Build..."
			ResourceProviders
            ErrorCheck -FunctionName "ResourceProviders"
			LightHouseConnection
            ErrorCheck -FunctionName "LightHouseConnection"
			DeploySentinel
            ErrorCheck -FunctionName "DeploySentinel"
            PolicyCreation
            ErrorCheck -FunctionName "PolicyCreation"
			RetentionSet
            ErrorCheck -FunctionName "RetentionSet"
			DataConnectors
            ErrorCheck -FunctionName "DataConnectors"
			DeployAnalyticalRules 
			ErrorCheck -FunctionName "DeployAnalyticalRules"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the main menu"
            [void][System.Console]::ReadKey($true)
			MainMenu
        }
    }
}

function ExistingBuild {
    $subMenu2 = 'X'
    Clear-Host
    GatherInfo
    while($subMenu2 -notin 'q', 'Q'){
        Clear-Host
        Write-Host "`n`t`t Finish Exisiting Build`n"
        Write-Host -ForegroundColor Cyan "Deploy Build Components"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Register Resource Providers"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Create Lighthouse Connection"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "3"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Deploy Sentinel Workspace"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "4"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Create Policies"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "5"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Set Table Retention"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "6"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Deploy Data Connectors"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "7"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Deploy Analytical Rules"
		
        $subMenu2 = Read-Host "`nSelection (q to return to main menu)"

        # Option 1
        if($subMenu2 -eq 1){
			Clear-Host
			Write-Host "`nRegistering resource providers..."
            ResourceProviders
			ErrorCheck -FunctionName "ResourceProviders"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
        # Option 2
        if($subMenu2 -eq 2){
			Clear-Host
			Write-Host "`nCreating Lighthouse connection..."
            LightHouseConnection
			ErrorCheck -FunctionName "LightHouseConnection"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 3
        if($subMenu2 -eq 3){
			Clear-Host
			Write-Host "`nDeploying Sentinel workspace..."
            DeploySentinel
			ErrorCheck -FunctionName "DeploySentinel"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 4
        if($subMenu2 -eq 4){
			Clear-Host
			Write-Host "`nCreating the policies..."
            PolicyCreation
			ErrorCheck -FunctionName "PolicyCreation"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
        # Option 5
        if($subMenu2 -eq 5){
			Clear-Host
			Write-Host "`nSetting table retention..."
            RetentionSet
			ErrorCheck -FunctionName "RetentionSet"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 6
        if($subMenu2 -eq 6){
			Clear-Host
			Write-Host "`nDeploying data connectors..."
            DataConnectors
			ErrorCheck -FunctionName "DataConnectors"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 7
        if($subMenu2 -eq 7){
			Clear-Host
			Write-Host "`nDeploying analytical rules..."
            DeployAnalyticalRules
			ErrorCheck -FunctionName "DeployAnalyticalRules"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
    }
}

function CleanUp{
    Write-Host "Remove Item"
    Remove-Item -Recurse -Path $FilePath
    $ErrorActionPreference = 'Continue'
    $ErrorView = 'NormalView'
}

MainMenu
CleanUp