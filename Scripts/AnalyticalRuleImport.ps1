$LinuxRules = "someurl"
$WinRules = "someURl"

Write-Output "What Analytical rules would you like to import to the Sentinel instance?

1.) All
2.) Primary (Win,Linux,Multi-Source,Network)
3.) Specify name (Insert list of names for rules which can likely be done through the creation of a array for the names.)
4.) All Rule types
5.) List out Existing rules"

$Subscription = Read-Host "what is the customer account which you would like to importat rules to?"

az account list --query '[].name' --output table

az context set -s $Subscription

Write-Host "You will need to know the log analytics workspace of the customer. 

Unsure? Select one of our greatest "

function ImportAll{
$WorkSpaceName = az monitor log-analytics workspace list --query '[].name'
$ResourceGroups = az group list --query '[].name' --output table | Select-String 'AzureSentinel'

foreach($Rule in $Rules){
    #The below needs to be modified with the template uri instead of template file initialization. This will ensure that we can use a array which has the values of all our template files. 
    az deployment group create --resource-group $ResourceGroups --template-file $Rule --parameter worksapce="$WorkSpaceName"
}
}