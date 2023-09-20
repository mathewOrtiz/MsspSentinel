#Global Variable initialized
$ErrorActionPreference = 'SilentlyContinue'
$ErrorView = 'CategoryView'
$ProgressPreference = 'SilentlyContinue'
$DefaultColor = [ConsoleColor]::Cyan
$pattern = "^H\d+AzureSentinel$"
$SocLevel1Id = (Get-AzADGroup -SearchString "SocLevel1").Id
$SocLevel2Id = (Get-AzADGroup -SearchString "SocLevel2").Id
$SocEngId = (Get-AzADGroup -SearchString "Security Engineering").Id
$SentinelReadersId = (Get-AzADGroup -SearchString "SentinelReaders").Id
$ProvTeamId = (Get-AzAdGroup -SearchString "ProvTeam").Id
$AutomationId = (Get-AzAdGroup -SearchString "Automation").Id
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
$UserAccessAdmin = (Get-AzRoleDefinition -Name 'User Access Administrator').Id
$KeyVaultContrib = (Get-AzRoleDefinition -Name 'Key Vault Contributor').Id
$AzureConnectedMachineOnboard = (Get-AzRoleDefinition -Name 'Azure Connected Machine Onboarding').Id
$HybridServerOnboard = (Get-AzRoleDefinition -Name 'Hybrid Server Onboarding').Id
$KubernetesClusterOnboard = (Get-AzRoleDefinition -Name 'Kubernetes Cluster - Azure Arc Onboarding').Id
$StorageAccountContrib = (Get-AzRoleDefinition -Name 'Storage Account Contributor').Id
$DisplayNameEng = "Security Engineer"
$DisplayNameL1 = "SOC L1"
$DisplaynameL2 = "SOC L2"
$DisplayNameReaders = "SOC Readers"
$Prov = "ProvTeam"
$AutomationName = "Automation"
$global:HomeContext = (Get-AzContext).Tenant.Id
$global:FunctionsToCheck = @{}
$global:AzSubscription = ""
$global:Location = ""
$global:CustHNumber = ""
$global:StorageAccount = "scriptsentinel"
$global:StorageContainer = "analyticalrules"

function GatherInfo{
    #The following is used in order to configure the necessary context to the new customer subscription.
    do{
        Write-Host "Enter in the tenant ID of the subscription that you need to deploy Sentinel.
    
This can be retrieved from the Azure AD overview page. Customer Tenant ID: " -Foregroundcolor $DefaultColor -NoNewline
        $NewInstance = Read-Host 
    }
    while($NewInstance -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')
    
    $temp = Set-AzContext -Tenant $NewInstance

    do{
        Write-Host "Enter the subscription ID you would like to deploy the solution: " -Foregroundcolor $DefaultColor -NoNewline
        $NewSub = Read-Host
    }
    while($NewSub -notmatch '^[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}$')

    do{
        Write-Host "Please enter the customer H#: " -NoNewline -ForegroundColor $DefaultColor
        $global:CustHNumber = Read-Host
    }
    while($global:CustHNumber -notmatch '^H\d+$')

    #After setting our context to the necessary customer tenant we grab the Subscription ID to use later on for Analytical rule import.
    $global:AzSubscription = (Get-AzContext).Subscription.Id

    do{
        Write-Host "Enter the location to deploy (Options: eastus or westus): " -NoNewline -ForegroundColor $DefaultColor
        $global:Location = Read-Host
    }
    while($global:Location -notin "eastus", "westus")

    #Creating the static variables to use for housing errors for the error check portion of the scipt. This hashtable will have all of the necessary errors. 
    $global:FunctionsToCheck = @{}
    $error.Clear()
}

#Begin the functions 
function ResourceProviders{
    #The below needs to be populated With the necessary namespaces as well as creating a array with the required resource providers.
    $RequiredProviderCheck =  @('Microsoft.SecurityInsights', 'Microsoft.OperationalInsights','Microsoft.PolicyInsights','Microsoft.HybridConnectivity','Microsoft.ManagedIdentity','Microsoft.AzureArcData','Microsoft.OperationsManagement','microsoft.insights','Microsoft.HybridCompute','Microsoft.GuestConfiguration','Microsoft.Automanage','Microsoft.MarketplaceNotifications','Microsoft.ManagedServices', 'Microsoft.Web')
    
    #The following loop will work through the subscription in order to register all of the resource providers we need for our resources. 
    foreach($Provider in $RequiredProviderCheck){
        $ProviderName = (Get-AzResourceProvider -ProviderNamespace $Provider).RegistrationState | Select-Object -First 1
        if($ProviderName -match "NotRegistered"){
            Write-Host 'Registering resource provider ' -NoNewline
            Write-Host $Provider -ForegroundColor $DefaultColor
            $temp=Register-AzResourceProvider -ProviderNamespace $Provider
        }
    }
}

#Function to create the necessary connection to our main tenant. 
function LightHouseConnection{
    $SocL1ObjectId = $SocLevel1Id
    $SocL2ObjectId = $SocLevel2Id
    $SocEngObjectId = $SocEngId
    $SentinelReaders = $SentinelReadersId
    $TenantId = $global:HomeContext
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
                    principalId = $SocEngObjectId
                    roleDefinitionId = $UserAccessAdmin
                    principalIdDisplayName = "$DisplayNameEng"
                    delegatedRoleDefinitionIds = @(
                        $AzureConnectedMachineOnboard
                        $HybridServerOnboard
                        $KubernetesClusterOnboard
                    )
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $KeyVaultContrib
                    principalIdDisplayName = "$DisplayNameEng"
                }
                @{
                    principalId = $SocEngObjectId
                    roleDefinitionId = $StorageAccountContrib
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
                @{
                    principalId = $ProvTeamId
                    roleDefinitionId = $TagContrib
                    principalIdDisplayName = $Prov
                }
                @{
                    principalId = $ProvTeamId
                    roleDefinitionId = $VirtualMachineContrib
                    principalIdDisplayName = $Prov
                }
                @{
                    principalId = $ProvTeamId
                    roleDefinitionId = $ResourcePolicyContrib
                    principalIdDisplayName = $Prov
                }
                @{
                    principalId = $ProvTeamId
                    roleDefinitionId = $ArcConnected
                    principalIdDisplayName = $Prov
                }
                @{
                    principalId = $AutomationId
                    roleDefinitionId = $SentinelResponder
                    principalIdDisplayName = $AutomationName
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

    $DirectoryName = "/home/Sentinel" + (Get-Date -Format "MMddyyyyHHmm")
    $FilePath = New-Item -ItemType Directory $DirectoryName

    #Converts the above to a JSON formatted file to be used for the ARM template push. 
    $MainObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $FilePath/TemplateParam.json

    Write-Host 'Establishing Azure Lighthouse connection'
    $temp = Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/Azure-Lighthouse-samples/master/templates/delegated-resource-management/subscription/subscription.json -OutFile $FilePath/ArmTemplateDeploy.json 
    $temp = New-AzDeployment -TemplateFile $FilePath/ArmTemplateDeploy.json -TemplateParameterFile $FilePath/TemplateParam.json -Location $global:Location

    Remove-Item -Recurse -Path $FilePath
}

function DeploySentinel{
    #Once the above has completed we have ensured that the necessary providers for the rest of our task have been completed
    #in the below lines we setup our variables which will be used later. We enforce the checking by using a dynamic regex check

    $Tag = @{
        "Production" = "False"
    }

	$global:CustHNumber += "AzureSentinel"

    do{        
        Write-Host "`nConfirm the following..." -ForegroundColor $DefaultColor
        Write-Host "Sentinel Workspace and Resource Group Name: " -NoNewline
        Write-Host $global:CustHNumber -ForegroundColor $DefaultColor
        Write-Host "Location: " -NoNewline
        Write-Host $global:Location -ForegroundColor $DefaultColor
        Write-Host "`nProceed (y/n): " -NoNewline
        $confirm = Read-Host
    }
    while($confirm -ne 'y')

    #Deploys the resource group which will house the Sentinel resources. 
    Write-Host "Deploying the resource group"
    $temp = New-AzResourceGroup -Name $global:CustHNumber -Location $global:Location

    #using the match regex we are able to ensure we grab only the resource group that we created in the previous step of variable init. 
    $ResourceGroupName = (Get-AzResourceGroup).ResourceGroupName

    Write-Host "Deploying the log analytics workspace"
    $temp = New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $global:CustHNumber -Location $global:Location -Tag $Tag -Sku pergb2018

    #Deploy Sentinel
    Write-Host "Deploying Sentinel"
    $temp = New-AzSentinelOnboardingState -ResourceGroupName $global:CustHNumber -WorkspaceName $global:CustHNumber -Name "default"
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
    Write-Host "Assigning Azure policies"
    $temp = New-AzPolicyAssignment -Name $WinAssignName -PolicyDefinition $DefinitionWin -PolicyParameterObject @{"logAnalytics"="$WorkspaceName"} -AssignIdentity -IdentityType SystemAssigned -Location $global:Location -WarningAction Ignore
    $temp = New-AzPolicyAssignment -Name $LinAssignName -PolicyDefinition $DefinitionLinux -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -IdentityType SystemAssigned -Location $global:Location -WarningAction Ignore
    $temp = New-AzPolicyAssignment -Name $ActivityName -PolicyDefinition $DefinitionActivity -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -IdentityType SystemAssigned -Location $global:Location -WarningAction Ignore
    #Now we need to fetch the policy -Id of the above. 
    
    $PolicyAssignWind = (Get-AzPolicyAssignment -Name $WinAssignName -WarningAction Ignore).PolicyAssignmentId
    $PolicyAssignLinux = (Get-AzPolicyAssignment -Name $LinAssignName -WarningAction Ignore).PolicyAssignmentId
    $PolicyAssignActivity = (Get-AzPolicyAssignment -Name $ActivityName -WarningAction Ignore).PolicyAssignmentId 
    
    Write-Host "Starting Azure policy remediation"
    $temp = Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignWind -Name WindowsOmsRemediation
    $temp = Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignLinux -Name LinuxOmsRemediation
    $temp = Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignActivity -Name AzureActivityLogRemediation
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
    Write-Host 'Updating retention settings for all tables to' -NoNewline
    Write-Host ' 90 days' -NoNewline -ForegroundColor $DefaultColor
    Write-Host ' hot storage and' -NoNewline
    Write-Host ' 365 days' -NoNewline -ForegroundColor $DefaultColor
    Write-Host ' cold storage'
    $tables.ForEach({
        $temp = Update-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -TableName $_ -RetentionInDays 90 -TotalRetentionInDays 365 -AsJob
    })  
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

    $DirectoryName = "/home/Sentinel" + (Get-Date -Format "MMddyyyyHHmm")
    $FilePath = New-Item -ItemType Directory $DirectoryName

    #Enables Common Security Event logs by pulling the template file we need from github & passing the parameters inline.
    Write-Host 'Enabling Common Security Event logs'
    $temp = Invoke-WebRequest -Uri $Uri -OutFile $FilePath/NtiretySecurityWinEvents.json
    $temp = New-AzResourceGroupDeployment -TemplateFile $FilePath/NtiretySecurityWinEvents.json -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroup -securityCollectionTier Recommended -AsJob
    
    #Deploys our other Win & Linux system logs.
    Write-Host 'Configuring data connector for Windows log sources'
    $WinLogSources.ForEach({
        $temp = New-AzOperationalInsightsWindowsEventDataSource -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Name $_ -CollectErrors -CollectWarnings -CollectInformation -EventLogName $_
    })
    Write-Host 'Configuring data connector for Linux log sources'
    $LinuxLogSources.ForEach({
        $temp = New-AzOperationalInsightsLinuxSyslogDataSource -Name $_ -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Facility $_ -CollectEmergency -CollectAlert -CollectCritical -CollectError -CollectWarning -CollectNotice
    })

    Remove-Item -Recurse -Path $FilePath
}

#This function creates a new service principal for Azure ARC installs.
function CreateNewServicePrincipal{
	Write-Host "`nCreating new service principal for Azure ARC installs" -ForegroundColor green
	$Sentinel = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "False"}) | Select-Object -Property Name, ResourceGroupName
	$ResourceGroupId = (Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -eq $Sentinel.ResourceGroupName}).ResourceId
	$AzureArcSp = New-AzADServicePrincipal -DisplayName $AzureArcSpName -Role "Azure Connected Machine Onboarding" -EndDate "2030-12-31T05:00:00Z" -Scope $ResourceGroupId
	
	Write-Host "`nService Principal App ID = " -NoNewline
	Write-Host $AzureArcSp.AppId -ForegroundColor cyan
	Write-Host "Service Principal App Secret = " -NoNewline
	Write-Host $AzureArcSp.PasswordCredentials.SecretText -ForegroundColor cyan
	Write-Host "`nPlease add the Service Principal App Secret to CMDB for the customer as a new credential." -ForegroundColor yellow
	
	do{
		Write-Host "`nOnce the app secret is gone it cannot be retrieved later. Make sure you copy the app secret before proceeding." -ForegroundColor red
		Write-Host "Did you copy the app secret and add it to CMDB (y/n)? "  -NoNewline
		$confirm = Read-Host
	}
	while($confirm -ne 'y')
}

#This function will check if there is an exisitng service principal for Azure ARC installs.
#If not it will create one. If there is it will ask to delete the existing and then create a new one.
function ServicePrincipal{
	$AzureArcSpName = "MsspAgentDeploy"
	$AzureArcSp = Get-AzADServicePrincipal -DisplayName $AzureArcSpName

	if($null -eq $AzureArcSp){
		CreateNewServicePrincipal
	}
	else{
		Write-Host "`nService principal for Azure ARC installs already exists." -ForegroundColor green
		do{
			Write-Host "Do you want to delete the existing one and create a new one (y/n)? "  -NoNewline
			$confirm = Read-Host
		}
		while($confirm -ne 'y' -and $confirm -ne 'n')
		
		if($confirm -eq 'y'){
			Write-Host "`nDeleting service principal " -NoNewline -ForegroundColor red
			Write-Host $AzureArcSpName -NoNewline
			Remove-AzADServicePrincipal -DisplayName $AzureArcSpName
			
			CreateNewServicePrincipal
		}
	}
}

#This function will need to be configured in order to get us our output that will 
function DeployAnalyticalRules {
    #The following below is used in order to set our context working directory back to our primary Sentinel tenant. We then reauth to the subscription under this AD user versus our Ntirety Principal User.
    $temp = Set-AzContext -Tenant $global:HomeContext -Subscription $global:AzSubscription

	#Get-AzContext

    #We create the storage context which will use our Azure AD credentials to authenticate to the Blob in order to auth to our files
    $StorageAccAuth = (New-AzStorageContext -StorageAccountName $global:StorageAccount)
    #$ContainerName = ((Get-AzStorageContainer -Context $StorageAccAuth).Name)
    $AnalyticalRules = @((Get-AzStorageBlob -Context $StorageAccAuth -Container $global:StorageContainer).Name)   
    #$ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Where-Object {$_ -match $pattern})
    #$WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Where-Object {$_ -match $pattern})
    $Sentinel = (Get-AzOperationalInsightsWorkspace | Where-Object {$_.Tags.Production -eq "False"}) | Select-Object -Property Name, ResourceGroupName
    $WorkspaceName = $Sentinel.Name
    $ResourceGroup = $Sentinel.ResourceGroupName
    $DirectoryName = "/home/Sentinel" + (Get-Date -Format "MMddyyyyHHmm")
    $FilePath = New-Item -ItemType Directory $DirectoryName

    #The following will download all of the files to our working directory. 
    Write-Host 'Downloading analytical rules from Azure storage conatiner ' -NoNewline
    Write-Host $global:StorageAccount -ForegroundColor $DefaultColor

    $AnalyticalRules.foreach({
        $temp = Get-AzStorageBlobContent -Context $StorageAccAuth -Blob $_ -Container $global:StorageContainer -Destination $FilePath
    })

	Write-Host "Deploying rules to resource group " -NoNewline
	Write-Host $ResourceGroup -NoNewline -ForegroundColor cyan
	Write-Host " and workspace " -NoNewline
	Write-Host $WorkspaceName -NoNewline -ForegroundColor cyan
    Write-Host ""
    #Can use the raw JSON files in order to deploy the analytical rules the params that are needed are the workspace & potentially the region.
    $AnalyticalRules.ForEach({
        $temp = New-AzResourceGroupDeployment -Name $_ -ResourceGroupName $ResourceGroup -TemplateFile $FilePath/$_ -Workspace $WorkspaceName -AsJob
        Write-Host 'The analytical rule set ' -NoNewline
        Write-Host $_ -ForegroundColor $DefaultColor -NoNewline
        Write-Host ' is being deployed'
    })

    Remove-Item -Recurse -Path $FilePath
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
        Write-Host "The following parts of the deployment had errors: " -ForegroundColor Red
        Write-Host $global:FunctionsToCheck.Keys -ForegroundColor $DefaultColor
        Write-Host "    -" $global:FunctionsToCheck[$FunctionName]
    }
    else {
        Write-Host "The previous part of the deployment had no errors." -ForegroundColor Green
    }
    
}

function WelcomeBanner{
    Clear-Host
    Write-Host "============================================================" 
    Write-Host "`t    _   _  _    _             _" -ForegroundColor $DefaultColor         
    Write-Host "`t   | \ | || |  (_)           | |" -ForegroundColor $DefaultColor            
    Write-Host "`t   |  \| || |_  _  _ __  ___ | |_  _   _" -ForegroundColor $DefaultColor    
    Write-Host "`t   |     || __|| || '__|/ _ \| __|| | | |" -ForegroundColor $DefaultColor    
    Write-Host "`t   | |\  || |_ | || |  |  __/| |_ | |_| |" -ForegroundColor $DefaultColor    
    Write-Host "`t   |_| \_| \__||_||_|   \___| \__| \__, |" -ForegroundColor $DefaultColor    
    Write-Host "`t                                    __/ |" -ForegroundColor $DefaultColor    
    Write-Host "`t                                   |___/ " -ForegroundColor $DefaultColor
    Write-Host "============================================================"      
    Write-Host "`nWelcome to the Ntirety Sentinel Deployment Script`n"
    Write-Host "Written by Mat Ortiz with a little help from Marc Ackermann"
    Write-Host "Any bugs or issues....hit up Mat :)"
    Write-Host "Version: 1.2"
    Write-Host "Release Date: September 20th, 2023"
    Write-Host "`nPlease choose a menu option below to get started"-ForegroundColor $DefaultColor
}

function MainMenu {
    $mainMenu = 'X'

    WelcomeBanner

    while($mainMenu -notin 'q', 'Q'){
        Write-Host "`n-----------------------------"
        Write-Host -ForegroundColor Cyan "          Main Menu"
        Write-Host "-----------------------------"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "1"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " New Build"
        Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "2"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
            Write-Host -ForegroundColor DarkCyan " Finish Existing Build"
        Write-Host "`n-----------------------------"
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
        Write-Host -ForegroundColor Magenta "Type YES to continue with new build"

        $subMenu1 = Read-Host "`nSelection (q to return to main menu)"

        # Continue
        if($subMenu1 -eq 'YES'){
			Clear-Host
            Write-Host "`nDeploying Sentinel Build..."
            Write-Host "`nRegistering resource providers..."
			ResourceProviders
            ErrorCheck -FunctionName "ResourceProviders"
            Write-Host "`nCreating Lighthouse connection..."
			LightHouseConnection
            ErrorCheck -FunctionName "LightHouseConnection"
            Write-Host "`nDeploying Sentinel workspace..."
			DeploySentinel
            ErrorCheck -FunctionName "DeploySentinel"
            Write-Host "`nCreating the policies..."
            PolicyCreation
            ErrorCheck -FunctionName "PolicyCreation"
            Write-Host "`nSetting table retention..."
			RetentionSet
            ErrorCheck -FunctionName "RetentionSet"
            Write-Host "`nDeploying data connectors..."
			DataConnectors
            ErrorCheck -FunctionName "DataConnectors"
			Write-Host "`nCreating new service principal..."
            ServicePrincipal
			ErrorCheck -FunctionName "ServicePrincipal"
            Write-Host "`nDeploying analytical rules..."
			DeployAnalyticalRules 
			ErrorCheck -FunctionName "DeployAnalyticalRules"
            # Pause and wait for input before going back to the menu
            Write-Host "`nSentinel deployment complete!" -ForegroundColor DarkCyan 
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
            Write-Host -ForegroundColor DarkCyan " Create Service Principal"
		Write-Host -ForegroundColor DarkCyan -NoNewline "`n["; Write-Host -NoNewline "8"; Write-Host -ForegroundColor DarkCyan -NoNewline "]"; `
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
			Write-Host "`nCreating new service principal..."
            ServicePrincipal
			ErrorCheck -FunctionName "ServicePrincipal"
            # Pause and wait for input before going back to the menu
            Write-Host -ForegroundColor DarkCyan "`nScript execution complete!"
            Write-Host "`nPress any key to return to the previous menu"
            [void][System.Console]::ReadKey($true)
        }
		# Option 8
        if($subMenu2 -eq 8){
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
    $ErrorActionPreference = 'Continue'
    $ErrorView = 'NormalView'
    $ProgressPreference = 'Continue'
}

MainMenu
CleanUp