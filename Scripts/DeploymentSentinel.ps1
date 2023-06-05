#Global Variable initialized
$pattern = "^\d{5}AzureSentinel$"

function ResourceProviders{
#The below needs to be populated With the necessary namespaces as well as creating a array with the required resource providers.
$ResourceProivder = @(Get-AzResourceProvider -ProviderNamespace)
$RequiredProviders =  @('Microsoft.SecurityInsights', 'Microsoft.OperationalInsights','Microsoft.PolicyInsights')
#Need to add here the fetching of the necessary files.

#Check to see if we need to register additional resource providers before running our ARM template.
$MissingProviders = @()

$NecessaryProviders = $true
#need to evaluate if calling the array through the in-built for method will be more efficient.
foreach ($value in $RequiredProviders){
    if (!($ResourceProivder -contains $value)){
        $NecessaryProviders = $false
        $MissingProviders += $MissingProviders
    }
}

if($NecessaryProviders -eq $false){
    foreach ($MissingProvider in $MissingProviders){
        Register-AzResourceProvider -ProviderNamespace $RequiredProvider
    }
}
}

function DeploySentinel{
#Once the above has completed we have ensured that the necessary providers for the rest of our task have been completed

#in the below lines we setup our variables which will be used later. We enforce the checking by using a dynamic regex check
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="Please enter the name of the customer using the format H#AzureSentinel")]
    [ValidatePattern('$pattern')]
    [string]
    $CustName,

    [Parameter(Mandatory=$true, HelpMessage="Please enter the location that is closet to this customer. Using the foramt eastus,westus etc")]
    [ValidatePattern('^([a-z]{2}-[a-z]{2}-\d{1})$')]
    [string]
    $location
)

#Initialize the Parameters to be used in our deployment
$TemplateParameters =@{
    workspaceName = $CustName
    location = $location
    sku = PerGB2018
    dataRetention = 90
}

New-AzResourceGroupDeployment -Name $CustName -TemplateParameterObject $TemplateParameters -ResourceGroupName $CustName -AsJob[PSCustomObject]@{
    Name = SentinelResourceDeploy
}

#We have now deployed the LogAnalytics Workspace & Sentinel Instance
}
function PolicyCreation{
#Creating the necessary policies
#$Subscription = (Get-AzContext).Subscription.Id
#$ResourceGroup = Get-AzResourceGroup | Select-String -Pattern $pattern
$WorkspaceName = Get-AzOperationalInsightsWorkspace | Select-String $pattern

$PolicyParam = @{
    "logAnalytics" = $WorkspaceName
}


#Grabs our policy Definition for use in the next step. 
$DefinitionWin = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Windows servers' }
$DefinitionLinux = Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Linux servers.'}

#begin creation of our new policy

#need to see if the variables being assigned here is really necessary. 
$DeployWinPolicy = New-AzPolicyAssignment -PolicyDefinition $DefinitionWin -PolicyParameterObject $PolicyParam -Name WindowsOmsInstaller -AssignIdentity -IdentityType SystemAssigned
$DeployLinuxPolicy = New-AzPolicyAssignment -PolicyDefinition $DefinitionLinux -PolicyParameterObject $PolicyParam -Name LinuxOMsInstaller -AssignIdentity -IdentityType SystemAssigned
#Now we need to fetch the policy -Id of the above. 

Start-AzPolicyRemediation -PolicyAssignmentId $DefinitionWin.PolicyDefinitionId -Name WindowsOmsRemediation
Start-AzPolicyRemediation -PolicyAssignmentId $DefinitionLinux.PolicyDefinitionId -Name LinuxOmsRemediation
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

#Deploy the Bicep Template

#Convert the defined template to proper JSON 
New-Item -ItemType Directory /home/WorkingDir

$TemplateToJson = Convert-ToJson $Template -Depth 100

$TemplateToJson | Out-File /home/workingDir/WindowsLogging.json

New-AzResourceGroupDeployment -TemplateFile WindowsLogging.json -Name WinLog

Wait-Job -Name WinLog
}




#This function will need to be configured in order to get us our output that will 
function DeployAnalyticalRules {
    #We create the storage context which will use our Azure AD credentials to authenticate to the Blob in order to auth to our files
    [CmdletBinding()]
    param (

    #In the below parameters need to ensure that we add a pattern matching feature. This will ensure that we aren't relying on the users input.
        [Parameter(DontShow)]
        [hashtable]
        $StorageAccAuth = (New-AzStorageAccountContext -StorageAccountName $StorageAccount ),

        [Parameter(DontShow)]
        [String]
        $StorageAccount = ((Get-AzStorageAccount).StorageAccountName),

        [Parameter(DontShow)]
        [String]
        $ContainerName = ((Get-AzStorageContainer -Context $StorageAccAuth).Name),

        [Parameter(DontShow)]
        [array]
        $AnalyticalRules = ((Get-AzStorageBlob -Context $StorageAccAuth).Name),

        [Parameter(DontShow)]
        [String]
        $ResourceGroup = ((Get-AzResourceGroup).Name -match $pattern),

        [Parameter(DontShow)]
        [Hashtable]
        $TemplateParams = @{
            workspace = Get-AzOperationalInsightsWorkspace -match $pattern
        }

    )
    #Need to in this step iterate over the array that we created while also deploying ARM templates. Need to ensure that this is done in the correct manner.

    #Can use the raw JSON files in order to deploy the analytical rules the params that are needed are the workspace & potentially the region.

    $AnalyticalRules.ForEach({New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $_ -TemplateParameterObject $TemplateParams -Name $_ -AsJob
        Write-Output 'The Analytical Rule Set for $_ Is being deployed once this has completed the next one will deploy'
    Wait-Job -Name $_
    })

}