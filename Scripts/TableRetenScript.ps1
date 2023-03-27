$RetentionDays = 90
$RetentionTotal = 365

## The below function is used in order to set the retention for all of our tables to the standard 1 year setting. 
function RetentionSet{
#Creates a array with all of the subscriptions. 
$Subscriptions = @(az account list --query '[].name')


#Ensures that this is run against every subscription that we can reach. 
foreach ($Subscription in Subscriptions){

    #Collects our resource groups from each subscription and will associate itself with the resource group variable. 
    az context set $Subscriptions
    $ResourceGroups = az group list --query '[].name'
    $WorkspaceNames = az monitor log-analytics workspace list --query '[].name'

    if($WorkspaceNames -ne "" ){
    #Collects the necessary table names
    $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query '[].name' )
    foreach ($name in $names){
        Update-AzOperationalInsightsTable -ResourceGroupName $RgName -WorkspaceName $WorkName -TableName $name -RetentionInDays $RetenDays -TotalRetentionInDays $RetenTotal
        }
    }
    #the following will run when the LAW is empty
    else{
        continue
    }

    #the following will actually work through every table in the list to modify the retention that is set to meet our standards.

    foreach ($name in $names){
        Update-AzOperationalInsightsTable -ResourceGroupName $RgName -WorkspaceName $WorkName -TableName $name -RetentionInDays $RetenDays -TotalRetentionInDays $RetenTotal
        }
    
    
    
    }
}