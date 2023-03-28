$RetentionDays = 90
$RetentionTotal = 365

## The below function is used in order to set the retention for all of our tables to the standard 1 year setting. 
function RetentionSetAllCustomers{
#Creates a array with all of the subscriptions. 
$Subscriptions = @(az account list --query '[].name')

#Ensures that this is run against every subscription that we can reach. 
foreach ($Subscription in Subscriptions){

    #This line ensures that we are located in the first subscription out of our array that we created.
    az context set $Subscriptions
    #This will pull the Rgs and pull out only the ones that we created.
    $ResourceGroups = az group list --query '[].name' | Select-String 'H\d{6}'
    #The following below should only pull log analytics workspaces that are in line with our naming convention.
    $WorkspaceNames = az monitor log-analytics workspace list --query '[].name' | Select-String -Pattern 'H\d{6}'

    if($WorkspaceNames -ne "" ){
    #Collects the necessary table names
    $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query '[].name' )
    foreach ($table in $tables){
        az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceNames -n $table --retention-time $RetentionDays --total-retention-time $RetentionTotal
        }
    }
    #the following will run when the LAW is empty
    }
}