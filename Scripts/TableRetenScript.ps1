##The below needs to be wrapped in a function in order for it to be called individually. This will allow for us to create our second function which will create our CSV file of information.
function TableRetentionUpdate {
$RetentionDays = Read-Host "Please enter in the amount of hot storage that you would like. Keeping in mind that if you go over 90 which is the default you will incur additional fees."
$RetentionTotal = Read-Host "Please enter in the total amount of time that you would like to retain your logs for in days. This will change the amount of time that the logs are archived for."
#Creates a array with all of the subscriptions. 
$Subscriptions = @(az account list --query '[].id')


#Ensures that this is run against every subscription that we can reach. 
foreach ($Subscription in Subscriptions){

# this ensures that every subscription will have its own Job which is assigned to it at run time. Each job is labeled using the subscription of each customer that is reachable to the script.      
Start-Job -Name $Subscription--ScriptBlock {
    #Collects our resource groups from each subscription and will associate itself with the resource group variable. 
    az context set $Subscriptions
    $ResourceGroups = az group list --query '[].name'
    $WorkspaceNames = az monitor log-analytics workspace list --query '[].name'

    #Collects the necessary table names
    $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames)

    #the following will actually work through every table in the list to modify the retention that is set to meet our standards.
    foreach($table in $tables){
        az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceNames --retention-time $RetentionDays --total-retention-time $RetentionTotal
    }
    }
}
}

function RetentionAudit {
##Collect from all of our subscriptions the table retention settings. 
$Subscriptions = @(az account list --output table)
$CompliantRetention = 365

$NonCompliantTables = @()

foreach ($Subscription in Subscriptions){
    $NonCompliantTables = @()
    # the below will list out all of the tables by name & retention setting. Need to ensure that when this is completed that we can store the results as a variable & do a compare against the array to ensure that all of our values are the same.
    #$TableInfo = az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query "[].{totalRetentionInDays:totalRetentionInDays, name:name}"
    $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames)
    foreach ($table in $tables ){
        #
        $ConfiguredRetention = az monitor log-analytics workspace table show --resource-group testpoc --workspace-name TestPOC -n $table --query retentionInDays

        #the following below will use the IF statement in order to verify if the retention configured is correct. If it is not the table name is placed into the a array. 
        if($ConfiguredRetention  = $CompliantRetention)
        {
            Continue
        }else{
            $NonCompliantTables += $table
        }
        
    }
}

}
