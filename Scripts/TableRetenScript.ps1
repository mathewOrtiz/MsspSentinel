$RetentionDays = 90
$RetentionTotal = 365

## The below function is used in order to set the retention for all of our tables to the standard 1 year setting. 
function RetentionSetAllCustomers{
#Creates a array with all of the subscriptions. 
$Subscriptions = @(az account list --query '[].name')

#Ensures that this is run against every subscription that we can reach. 
foreach ($Subscription in Subscriptions){

    #This line ensures that we are located in the first subscription out of our array that we created.
    az account set --subscription $Subscriptions
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

function RetentionSpecificCust{
    az account list --output table 
    $Subscription = Read-Host "Please enter the subscription context for the customer that you are working with"
    az account set --$Subscription
    
    az group list --query '[].name'
    $ResourceGroups = Read-Host "Please enter the Resource group which contains the Log analytics workspace we will need to edit. "
    
    az monitor log-analytics workspace list --query '[].name'
    WorkspaceName = Read-Host "Please enter the log analytics workspace name that you would like to edit the retention for. "

    $RetenType = Read-Host "Would you like to edit all of the tables located within the subscription? or just change one specific tables retention setting? 
    1.) Proceed with changing retention for all tables
    2.) Proceed with only modifying a specific table. (Note that if you don't have the exact table name this command will not work.)
    "
    if ($RetenType = 1 ){
        $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query '[].name' )
        foreach ($table in $tables){
            az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceNames -n $table --retention-time $RetentionDays --total-retention-time $RetentionTotal
        }
    }
        elseif ($RetenType = 2 ){
        $TableName = Read-Host "Please enter the name of the table that you would like to edit. "
        az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceNames -n $TableName --retention-time $RetentionDays --total-retention-time $RetentionTotal
    }

    }


## The following function needs to be improved so that we can call the necessary info into the correct format into a CSV file    
#function RetentionAudit{
#   do{
#   $SubsToAudit = Read-Host "Would you like to audit all of the subscriptions or just one? 
#   1.) All Customers
#   2.) Just One Customer subscription
#   3.) Exit to Main menu
#
#   "
#   }until( $SubsToAudit -eq 1 -or $SubsToAudit -eq 2)
#
#   if($SubsToAudit = 1 ){
#   
#       $Subscriptions = @(az account list --query '[].name')
#       $TableRetenAllCust = @()
#   #Ensures that this is run against every subscription that we can reach. 
#   foreach ($Subscription in Subscriptions){
#
#   #This line ensures that we are located in the first subscription out of our array that we created.
#   az account set --subscription $Subscriptions
#   #This will pull the Rgs and pull out only the ones that we created.
#   $ResourceGroups = az group list --query '[].name' | Select-String 'H\d{6}'
#   #The following below should only pull log analytics workspaces that are in line with our naming convention.
#   $WorkspaceNames = az monitor log-analytics workspace list --query '[].name' | Select-String -Pattern 'H\d{6}'
#
#   #Ensures that our workspace name isn't empty & then runs using the Rg & WS name collected above. 
#   if($WorkspaceNames -ne "" ){
#   #Collects the necessary table names
#   $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query '[].{name:name,totalRetentionInDays:totalRetentionInDays}')| ConvertFrom-Json ` | Select-Object -Property name, totalRetentionInDays ` | Where-Object {$_totalRetentionInDays -le 365}
#   
#   #Adds the results of the retention to the 
#   $TableRetenAllCust += $tables
#   }
#   #the following will run when the LAW is empty
#   }
#   }
#
#}


function menu{
    param (
        [string]$Title = 'Select Option'
    )
    Clear-Host
    Write-Host "============ $Title ============"

    Write-Host "1.) Set all Customers Retention"
    Write-Host "2.) Set specific customers retention"
    Write-Host "3.) Find tables not in compliance"


#Begin check for user input

$MenuChoice = Read-Host "Enter the number for the utility that you would like to use"
switch($MenuChoice){
    1{RetentionSetAllCustomers}
    2{RetentionSpecificCust}
    3{RetentionAudit}
}

}
menu
