#Global Variable initialized
$pattern = "^H\d{5}AzureSentinel$"
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


#Sets the context for our script to run in. This is important as it will allow the user to remotely authenti
$NewInstance = Read-Host "Enter in the tenant ID of the subscription that you need to deploy the Sentinel resources for. "
Set-AzContext -Tenant $NewInstance
$AzSubscription = (Get-Azcontext).Name.Id
wait 10
Set-AzContext -Subscription $AzSubscription
#Creating the static variables to use for housing errors for the error check portion of the scipt. 
$FunctionsToCheck = @{}

#Used to make sure we don't get any extraneous errors. 
$error.Clear()
function ResourceProviders{
    #The below needs to be populated With the necessary namespaces as well as creating a array with the required resource providers.
    $RequiredProviderCheck =  @('Microsoft.SecurityInsights', 'Microsoft.OperationalInsights','Microsoft.PolicyInsights','Microsoft.HybridConnectivity','Microsoft.ManagedIdentity','Microsoft.AzureArcData','Microsoft.OperationsManagement','microsoft.insights','Microsoft.HybridCompute','Microsoft.GuestConfiguration','Microsoft.Automanage','Microsoft.MarketplaceNotifications','Microsoft.ManagedServices')
    #Need to add here the fetching of the necessary files.
    
    foreach($Provider in $RequiredProviderCheck){
        #$RequiredProviderCheck
    
        $ProviderName = (Get-AzResourceProvider -ProviderNamespace $Provider).RegistrationState | Select-Object -First 1
        $ProviderName
        if($ProviderName -match "NotRegistered"){
        Register-AzResourceProvider -ProviderNamespace $Provider
        }
}

#Catches any errors from this execution. 
if($error[0]){
    $error.ForEach({$FunctionsToCheck["ResourceProviders"] += $_.Exception.Message})
}
$error.Clear()
}
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

#Convert the above into a single JSON file that will work for the parameter file
$MainObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $FilePath/TemplateParam.json

Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/Azure-Lighthouse-samples/master/templates/delegated-resource-management/subscription/subscription.json -OutFile $FilePath/ArmTemplateDeploy.json
    
New-AzDeployment -TemplateFile $FilePath/ArmTemplateDeploy.json -TemplateParameterFile $FilePath/TemplateParam.json

if($error[0]){
$error.foreach({$FunctionsToCheck["LightHouse"] += $_.Exception.Message})
$error.Clear()
}
}

function DeploySentinel{
#Once the above has completed we have ensured that the necessary providers for the rest of our task have been completed

#in the below lines we setup our variables which will be used later. We enforce the checking by using a dynamic regex check
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="Please enter the name of the customer using the format H#AzureSentinel")]
    [ValidatePattern('^H\d{5}AzureSentinel$')]
    [string]
    $CustName,

    [Parameter(Mandatory=$true, HelpMessage="Please enter the location that is closet to this customer. Using the foramt eastus,westus etc")]
    [ValidatePattern('^([a-z0-9]+)$')]
    [string]
    $location
)

#Deploys the resource group which will house the Sentinel resources. 
New-AzResourceGroup -Name $CustName -Location $location

#using the match regex we are able to ensure we grab only the resource group that we created in the previous step of variable init. 
(Get-AzResourceGroup).ResourceGroupName
$ResourceGroupName = Read-Host "Enter in the Resource Group Name"

#The following pulls down the ARM template which is used by the SOC and then utilizes this connection in order to allow for the necessary changing of the workspace name. We grab the location dynamically when the script runs in this case. 
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mathewOrtiz/MsspSentinel/main/ARM/NtiretyMsspAzureResources.json' -OutFile $FilePath/NtiretyMsspAzureResources.json
$ArmContent = Get-Content -Raw -Path $FilePath/NtiretyMsspAzureResources.json | ConvertFrom-Json -AsHashtable
$ArmContent.parameters.workspaceName.defaultValue = $ResourceGroupName
$CompleteTemplate = $ArmContent | ConvertTo-Json -Depth 10
$CompleteTemplate |Set-Content -Path $FilePath/NtiretyMsspAzureResources.json


New-AzResourceGroupDeployment -TemplateFile $FilePath/NtiretyMsspAzureResources.json  -ResourceGroupName $CustName -WorkspaceName $CustName

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
        $WorkspaceName = ((Get-AzOperationalInsightsWorkspace).Name | Select-String -Pattern $pattern)
    )
    
    #Grabs our policy Definition for use in the next step. 
    $DefinitionWin = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Windows servers' }
    $DefinitionLinux = Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Linux servers. See deprecation notice below'}
    
    $WorkspaceName = (Get-AzOperationalInsightsWorkspace).Name
    $WorkspaceName
    
    #begin creation of our new policy
    
    #need to see if the variables being assigned here is really necessary. 
    New-AzPolicyAssignment -Name $WinAssignName -PolicyDefinition $DefinitionWin -PolicyParameterObject @{"logAnalytics"="$WorkspaceName"} -AssignIdentity -Location eastus
    New-AzPolicyAssignment -Name $LinAssignName -PolicyDefinition $DefinitionLinux -PolicyParameterObject @{"logAnalytics"="$workspaceName"} -AssignIdentity -Location eastus
    #Now we need to fetch the policy -Id of the above. 
    
    $PolicyAssignWind = (Get-AzPolicyAssignment -Name WindowsOmsInstaller).PolicyAssignmentId
    $PolicyAssignLinux = (Get-AzPolicyAssignment -Name $LinAssignName).PolicyAssignmentId 
    
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
        $WorkspaceName = (Get-AzOperationalInsightsWorkspace | Select-String $pattern),

        [Parameter( DontShow)]
        [String]
        $ResourceGroup = (Get-AzResourceGroup | Select-String -Pattern $pattern),

        [Parameter(DontShow)]
        [array]
        $tables = @((Get-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName))
    )
#Before beginning iteration through the table we query to ensure that our Job has been completed to deploy our Sentinel resources. If this hasn't been completed then we wait for it to finish.
$SentinelDeployStatus = (Get-Job -Name SentinelResourceDeploy).State

if($SentinelDeployStatus -eq "Running"){
Wait-Job -Name SentinelResourceDeploy

Write-Output "The Sentinel Resources are still being deployed please wait for this to be completed."\
#The below will re-run the sentinel deploy script in order to ensure that the necessary resources are created to be modified. 
}elseif($SentinelDeployStatus -eq "Failed"){
DeploySentinel

Wait-Job -Name SentinelResourceDeploy

Write-Output "The initial deployment of the Sentinel Resource has failed please wait while this is attempted again."
}else {
    $tables.ForEach({Update-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -TableName $_ })
}

$tables.ForEach({Update-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -TableName $_ })

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
        $ResourceGroup = (Get-AzResourceGroup | Select-String),

        [Parameter(DontShow)]
        [string]
        $WorkspaceName = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName),

        [Parameter(DontShow)]
        [array]
        $WinLogSources = @('System','Application'),

        [Parameter(DontShow)]
        [array]
        $LinuxLogSources = @('Auth','authpriv','syslog','cron'),


        #Defines our parameters for our arm temaple
        [Parameter(DontShow)]
        [hastable]
        $ParametersForTemplate = @{
            workspaceName =@{
                type = 'string'
                defaultvalue = $WorkspaceName
            }
            dataSourceName = @{
                type = 'string'
                defaultvalue = 'SecurityInsightsSecurityEventCollectionConfiguration'
            }
        },
        
        #Defines our resources for our Arm template
        [Parameter(DontShow)]
        [hastable]
        $ResoucesTemplate = @(
            @{
                "type" = "Microsoft.OperationalInsights/workspaces/dataSources"
                "apiVersion" = "2020-08-01"
                "name" = "[concat(parameters('workspaceName'), '/', parameters('dataSourceName'))]"
                "kind" = 'dataSourceName'
                    "properties" = @{
                        "tier" = 'Recommended'
                    }
            }
        ),

        #Define the ARM template
        [Parameter(DontShow)]
        [hastable]
        $Template = @{
            '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
            contentVersion = '1.0.0.0'
            parameters = $ParametersForTemplate
            resource = $ResoucesTemplate
        }
        
  )
    
#Creates our necessary log sources for the Oms agent log collection. This will need to be updated if we add in a new method for the ARC agent. 
$WinLogSources.ForEach({New-AzOperationalInsightsWindowsEventDataSource -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -EventLogName $WinLogSources})
$LinuxLogSources.ForEach({New-AzOperationalInsightsLinuxSyslogDataSource -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -EventLogName $LinuxLogSources})

#Creates the JSON template file from the above parameters we have set. 
$TemplateToJson = Convert-ToJson $Template -Depth 100

$TemplateToJson | Out-File $FilePath/WindowsLogging.json

New-AzResourceGroupDeployment -TemplateFile WindowsLogging.json -Name WinLog

Wait-Job -Name WinLog

if($error -ne $null){
    $error.ForEach({$FunctionToCheck["DataConnectors"] += $_.Exception.Message})
    $error.Clear()
}

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

    $AnalyticalRules.ForEach({New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $_ -TemplateParameterObject $TemplateParams -Name $_ -AsJob
        Write-Output 'The Analytical Rule Set for $_ Is being deployed once this has completed the next one will deploy'
    Wait-Job -Name $_
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