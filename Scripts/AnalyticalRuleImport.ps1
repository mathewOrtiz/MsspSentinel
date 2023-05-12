#Leverage SAS for the pull down of URLs.

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
function ImportAll{
$WorkSpaceName = az monitor log-analytics workspace list --query '[].name' | Select-String -Pattern "AzureSentinel"
$ResourceGroups = az group list --query '[].name' --output table | Select-String 'AzureSentinel'

foreach($Rule in $Rules){
    #The below needs to be modified with the template uri instead of template file initialization. This will ensure that we can use a array which has the values of all our template files. 
    az deployment group create --resource-group $ResourceGroups --template-file $Rule --parameter worksapce="$WorkSpaceName"
}
}
function menu{
$validResponse = @{
    "Import All Rules Available" = {ImportAll}
    "Primary (Win,Linux,Multi-Source,Network)" = {Primary}
    "Specify Name" = {SpecifyName}
    "All rule" = {AllRule}
    "Audit Existing" = {Audit}
}
do{
    $response = Read-Host "Please select one of the available utilities 
1.) All
2.) Primary (Win,Linux,Multi-Source,Network)
3.) Specify name (Insert list of names for rules which can likely be done through the creation of a array for the names.)
4.) All Rule types
5.) List out Existing rules"
}until ($validResponse.ContainsKey($response))

& $validResponse[$response]
}