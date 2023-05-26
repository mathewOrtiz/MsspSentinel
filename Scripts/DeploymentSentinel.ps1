#The below needs to be populated With the necessary namespaces as well as creating a array with the required resource providers.
$ResourceProivder = @(Get-AzResourceProvider -ProviderNamespace)
$RequiredProviders =  @('Microsoft.SecurityInsights', 'Microsoft.OperationalInsights','Microsoft.PolicyInsights')
$pattern = "^\d{5}AzureSentinel$"
#Need to add here the fetching of the necessary files.

#Check to see if we need to register additional resource providers before running our ARM template.
$MissingProviders = @()

$NecessaryProviders = $true
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

#Once the above has completed we have ensured that the necessary providers for the rest of our task have been completed
$NameForResources = Read-Host "Enter the primary H# for this customer."
$location = Read-Host "What azure region is the closest to this customer geograhpically?"

$CustId = $NameForResources + " AzureSentinel"

#Initialize the Parameters to be used in our deployment
$parameters =@{
    "workspaceName" = $CustId
    "location" = $location
    "sku" = "PerGB2018"
    ""
}

if($CustId -match $pattern){
   $SentinelResources = New-AzDeployment -TemplateFile -TemplateParameterObject $parameters -AsJob
}

#We have now deployed the LogAnalytics Workspace & Sentinel Instance

#Creating the necessary policies
$Subscription = (Get-AzContext).Subscription.Id
$ResourceGroup = Get-AzResourceGroup | Select-String -Pattern $pattern
$ResourceId = Get-AzOperationalInsightsWorkspace | Select-String $pattern

$PolicyParam = @{
    "logAnalytics" = $ResourceId
}

#Grabs our policy Definition for use in the next step. 
$Definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Windows servers' }
$Definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq 'Configure Log Analytics extension on Azure Arc enabled Windows servers' } | Select-Object DisplayName

#begin creation of our new policy
$DeployWinPolicy = New-AzPolicyAssignment -PolicyDefinition $Definition -PolicyParameter $PolicyParam -Name WindowsOmsInstaller -AssignIdentity -IdentityType SystemAssigned

#Now we need to fetch the policy -Id of the above. 

$NewPolicy = Get-AzPolicyDefinition -Name WindowsOmsInstaller
$NewPolicyId = $NewPolicy.PolicyDefinitionId

Start-AzPolicyRemediation -PolicyAssignmentId $NewPolicyId 
