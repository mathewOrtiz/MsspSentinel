#The below needs to be populated With the necessary namespaces as well as creating a array with the required resource providers.
$ResourceProivder = @(Get-AzResourceProvider -ProviderNamespace)
$RequiredProviders =  @('Microsoft.SecurityInsights', 'Microsoft.OperationalInsights','Microsoft.PolicyInsights')
$pattern = "^\d{5}AzureSentinel$"
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

$SentinelResources = New-AzResourceGroupDeployment -Name $CustName -TemplateParameterObject $TemplateParameters -ResourceGroupName $CustName

#We have now deployed the LogAnalytics Workspace & Sentinel Instance
}
function PolicyCreation{
#Creating the necessary policies
$Subscription = (Get-AzContext).Subscription.Id
$ResourceGroup = Get-AzResourceGroup | Select-String -Pattern $pattern
$WorkspaceName = Get-AzOperationalInsightsWorkspace | Select-String $pattern

$PolicyParam = @{
    "logAnalytics" = $WorkspaceName
}


#Grabs our policy Definition for use in the next step. 
$Definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Windows servers' }

#begin creation of our new policy
$DeployWinPolicy = New-AzPolicyAssignment -PolicyDefinition $Definition -PolicyParameter $PolicyParam -Name WindowsOmsInstaller -AssignIdentity -IdentityType SystemAssigned
$DeployLinuxPolicy
#Now we need to fetch the policy -Id of the above. 

$NewPolicy = Get-AzPolicyDefinition -Name WindowsOmsInstaller
$NewPolicyId = $NewPolicy.PolicyDefinitionId

Start-AzPolicyRemediation -PolicyAssignmentId $NewPolicyId 
}