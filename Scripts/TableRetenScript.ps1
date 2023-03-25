$RetentionDays = 90
$RetentionTotal = 365

#Creates a array with all of the subscriptions. 
$Subscriptions = @(az account list --query '[].name')


#Ensures that this is run against every subscription that we can reach. 
foreach ($Subscription in Subscriptions){

    #Collects our resource groups from each subscription and will associate itself with the resource group variable. 
    az context set $Subscriptions
    $ResourceGroups = az group list --query '[].name'
    $WorkspaceNames = az monitor log-analytics workspace list --query '[].name'

    #Collects the necessary table names
    $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames )

    #the following will actually work through every table in the list to modify the retention that is set to meet our standards.

    foreach($table in $tables){
        az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceNames
    }
    

    
}