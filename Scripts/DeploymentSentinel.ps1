#Global Variable initialized
$DefaultColor = [ConsoleColor]::Cyan
$pattern = "^H\d{4,5}AzureSentinel$"
$FilePath = New-Item -ItemType Directory /home/WorkingDir
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
$StorageAccountName = Read-Host "Enter the name of the storage account containing the analytical rules."
$HomeContext = Get-AzContext.Tenant.Id


#The following is used in order to configure the necessary context to the new customer subscription.
Write-Host "Enter in the tenant ID of the subscription that you need to deploy the Sentinel resources for.

This can be retrieved from the Azure AD overview page." -Foregroundcolor $DefaultColor
$NewInstance = Read-Host 
Set-AzContext -Tenant $NewInstance

Write-Host "Enter in the subscription ID you would like to deploy the solution too. " -Foregroundcolor $DefaultColor
$NewSub = Read-Host

Set-AzContext -Subscription $NewSub

#After setting our context to the necessary customer tenant we grab the Subscription ID to use later on for Analytical rule import.
$AzSubscription = (Get-AzContext).Subscription.Id


#Creating the static variables to use for housing errors for the error check portion of the scipt. This hashtable will have all of the necessary errors. 
$FunctionsToCheck = @{}
$error.Clear()

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

#End of For loop and beginning of error catching.  
if($error[0]){
    $error.ForEach({$FunctionsToCheck["ResourceProviders"] += $_.Exception.Message})
}
$error.Clear()
}

#Function to create the necessary connection to our main tenant. 
function LightHouseConnection{
$SocL1ObjectId = Read-Host "Enter the Principal ID for the SOC L1 group"
$SocL2ObjectId = Read-Host "Enter the PrincipalId for the SOC L2 Group"
$SocEngObjectId = Read-Host "Enter the Principal ID for the SOC Eng group"
$SentinelReaders = Read-Host "Enter the Principal ID for the Sentinel Readers Group"
$TenantId = Read-Host "Enter the Tenant ID for the home tenant"
#Creates our hashtable to utilize for the parameters for the JSON file.
$parameters = [ordered]@{
    mspOfferName = @{
        value = "Ntirety Lighthouse SOC"
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
    
New-AzDeployment -TemplateFile $FilePath/ArmTemplateDeploy.json -TemplateParameterFile $FilePath/TemplateParam.json

#Catches all our errors.
if($error[0]){
$error.foreach({$FunctionsToCheck["LightHouse"] += $_.Exception.Message})
$error.Clear()
}
}

#End the 
function DeploySentinel{
#Once the above has completed we have ensured that the necessary providers for the rest of our task have been completed

#in the below lines we setup our variables which will be used later. We enforce the checking by using a dynamic regex check
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="Please enter the name of the customer using the format H#AzureSentinel")]
    [ValidatePattern('^H\d+AzureSentinel$')]
    [string]
    $CustName,

    [Parameter(Mandatory=$true, HelpMessage="Please enter the location that is closet to this customer. Using the foramt eastus,westus etc")]
    [ValidatePattern('^([a-z0-9]+)$')]
    [string]
    $location,

    [Parameter(DontShow)]
    [Hashtable]
    $Tag = @{
        "Production" = "false"
    }
)

#Deploys the resource group which will house the Sentinel resources. 
New-AzResourceGroup -Name $CustName -Location $location

#using the match regex we are able to ensure we grab only the resource group that we created in the previous step of variable init. 
$ResourceGroupName = (Get-AzResourceGroup).ResourceGroupName


New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $CustName -Location $location -Tag $Tag -Sku pergb2018


#The following pulls down the ARM template which is used by the SOC and then utilizes this connection in order to allow for the necessary changing of the workspace name. We grab the location dynamically when the script runs in this case. 
#Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mathewOrtiz/MsspSentinel/main/ARM/NtiretyMsspAzureResources.json' -OutFile $FilePath/NtiretyMsspAzureResources.json
#$ArmContent = Get-Content -Raw -Path $FilePath/NtiretyMsspAzureResources.json | ConvertFrom-Json -AsHashtable
#$ArmContent.parameters.workspaceName.defaultValue = $ResourceGroupName
#$CompleteTemplate = $ArmContent | ConvertTo-Json -Depth 10
#$CompleteTemplate |Set-Content -Path $FilePath/NtiretyMsspAzureResources.json

#Deploy Sentinel
New-AzSentinelOnboardingState -ResourceGroupName $CustName -WorkspaceName $CustName -Name "default"

#Exist to catch errors associated with this run
if($error[0]){
    $error.ForEach({$FunctionsToCheck["DeploySentinel"] += $_.Exception.Message})
   $error.Clear()
    }
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
    
        [Parameter]
        [String]
        $ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Select-String -Pattern $pattern),
    
        [Parameter(DontShow)]
        [String]
        $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Select-String -Pattern $pattern),

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
    New-AzPolicyAssignment -Name $WinAssignName -PolicyDefinition $DefinitionWin -PolicyParameterObject @{"logAnalytics"="$WorkspaceName"} -AssignIdentity -Location eastus
    New-AzPolicyAssignment -Name $LinAssignName -PolicyDefinition $DefinitionLinux -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -Location eastus
    New-AzPolicyAssignment -Name $ActivityName -PolicyDefinition $DefinitionActivity -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -Location eastus
    #Now we need to fetch the policy -Id of the above. 
    
    $PolicyAssignWind = (Get-AzPolicyAssignment -Name WindowsOmsInstaller).PolicyAssignmentId
    $PolicyAssignLinux = (Get-AzPolicyAssignment -Name $LinAssignName).PolicyAssignmentId
    $PolicyAssignActivity = (Get-AzPolicyAssignment -Name = $ActivityName).PolicyAssignmentId 
    
    start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignWind -Name WindowsOmsRemediation
    Start-AzPolicyRemediation -PolicyAssignmentId $PolicyAssignLinux -Name LinuxOmsRemediation
    
    if($error -ne $null){
    $error.ForEach({$FunctionsToCheck["PolicyCreation"] += $_.Exception.Message})
    $error.Clear()
    }
    
    }
    
    #Sets our Table Retention 
    function RetentionSet{
        [CmdletBinding()]
        param (
            [Parameter(DontShow)]
            [String]
            $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Select-String $pattern),
    
            [Parameter( DontShow)]
            [String]
            $ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Select-String -Pattern $pattern),
    
            [Parameter(DontShow)]
            [array]
            $tables = @((Get-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName))
    
        )
    #Before beginning iteration through the table we query to ensure that our Job has been completed to deploy our Sentinel resources. If this hasn't been completed then we wait for it to finish.
    
    #The below will re-run the sentinel deploy script in order to ensure that the necessary resources are created to be modified. 
    
    $tables.ForEach({Start-Job -Name TableUpdate {Update-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -TableName $_}
    
    }
    )
    
    if($error -ne $null){
        $error.ForEach({$FunctionsToCheck["RetentionSet"] += $_.Exception.Message})
        $error.Clear
    }
    
    }
    
    function DataConnectors{
        [CmdletBinding()]
        param (
            [Parameter(DontShow)]
            [string]
            $ResourceGroup = ((Get-AzResourceGroup).ResourceGroupName | Select-String -Pattern $pattern),
    
            [Parameter(DontShow)]
            [string]
            $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Select-String -Pattern $pattern),
    
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

    Wait-Job
    
    #Deploys our other Win & Linux system logs.
    $WinLogSources.ForEach({New-AzOperationalInsightsWindowsEventDataSource -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Name $_ -CollectErrors -CollectWarnings -CollectInformation -EventLogName $_})
    $LinuxLogSources.ForEach({New-AzOperationalInsightsLinuxSyslogDataSource -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -Facility $_ -CollectEmergency -CollectAlert -CollectCritical -CollectError -CollectWarning -CollectNotice -EventLogName $_})

    if($error -ne $null){
        $error.ForEach({$FunctionToCheck["DataConnectors"] += $_.Exception.Message})
        $error.Clear()
    }
#The following below is used in order to set our context working directory back to our primary Sentinel tenant. We then reauth to the subscription under this AD user versus our Ntirety Principal User.
    Set-AzContext $HomeContext
    Set-AzContext $AzSubscription
    }



#This function will need to be configured in order to get us our output that will 
function DeployAnalyticalRules {
    #We create the storage context which will use our Azure AD credentials to authenticate to the Blob in order to auth to our files
    [CmdletBinding()]
    param (

    #In the below parameters need to ensure that we add a pattern matching feature. This will ensure that we aren't relying on the users input.
        [Parameter(DontShow)]
        [hashtable]
        $StorageAccAuth = (New-AzStorageContext -StorageAccountName $StorageAccountName),

        [Parameter(DontShow)]
        [String]
        $ContainerName = ((Get-AzStorageContainer -Context $StorageAccAuth).Name),

        [Parameter(DontShow)]
        [array]
        $AnalyticalRules = @((Get-AzStorageBlob -Context $StorageAccAuth).Name),

        [Parameter(DontShow)]
        [String]
        $ResourceGroup = ((Get-AzResourceGroup).Name -match $pattern),

        [Parameter(DontShow)]
        [Hashtable]
        $TemplateParams = @{
            workspace = Get-AzOperationalInsightsWorkspace -match $pattern
        }

    )
    #The following will need download all of the files to our working directory. 
    $AnalyticalRules.foreach({Get-AzStorageBlobContent -Context -Blob $_ -Container $ContainerName -Destination $FilePath})


    #Can use the raw JSON files in order to deploy the analytical rules the params that are needed are the workspace & potentially the region.

    $AnalyticalRules.ForEach({New-AzResourceGroupDeployment -Name $_ -ResourceGroupName $ResourceGroup -TemplateFile $_ -Workspace $WorkspaceName -AsJob
        Write-Output 'The Analytical Rule Set for $_ Is being deployed once this has completed the next one will deploy'
    })

}

function ErrorCheck{
    Write-Output "The following functions of the deployment had errors: " $FunctionsToCheck.Keys

    #needs menu option for what actions to be taken. Include all function calls. 
}

ResourceProviders
LightHouseConnection
DeploySentinel
RetentionSet
DataConnectors
DeployAnalyticalRules
ErrorCheck