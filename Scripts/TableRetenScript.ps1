$RetentionDays = 90
$RetentionTotal = 365
$pattern = '\d{5}AzureSentinel'

## The below function is used in order to set the retention for all of our tables to the standard 1 year setting. 
function RetentionSetAllCustomers{
#Creates a array with all of the subscriptions. The output parameter is added to the command in order to remove the quotation marks. 
$Subscriptions = @(Get-AzSubscription | Select-Object -ExpandProperty Id)
$Fail = @()

#This change to ForEach-Object was made so that it can run against every single subscription in parallel at the sametime this still needs to be tested however 
    ForEach-Object -Parallel {
    $Subscriptions = $_
    #Collects our resource groups from each subscription and will associate itself with the resource group variable. 
    # The following line shouldn't be needed if we can run the powershell cmdlets by passing the sub. az account set --subscription $Subscription

    #queries our current subscription to ensure that we have the necessary role to make the table updates. 
    $roleAssignments = Get-AzRoleAssignment | Where-Object {$_.RoleDefinitionName -eq 'Log Analytics Contributor' } | Select-Object -ExpandProperty RoleDefinitionName    Write-Output $Perms
    
    #the following below is added in to make sure that we only attempt to run the commands on subs where we are able to.
    if($roleAssignments -eq "Log Analytics Contributor"){

        $ResourceGroup = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -match $pattern } | Select-Object -ExpandProperty ResourceGroupName
        $WorkspaceName = Get-AzOperationalInsightsWorkspace | Where-Object {$_.Name -match $pattern } | Select-Object -ExpandProperty Name
        #Collects the necessary table names. This specifically queries only the names of the tables & ensures that we don't return any additional formatting just raw strings.
        $tables = @((Get-AzOperationalInsightsTable -ResourceGroup testpoc -WorkspaceName TestPOC)).Name

        #The following has been modified to use the foreach method as it has better compute performance inline. Will need to compare to the parrallel task as well.
        $tables.foreach({Update-AzOperationalInsightsTable -ResourceGroupName $ResourceGroup -WorkspaceName $WorkspaceName -TableName $_ -RetentionInDays $RetentionDays -TotalRetentionInDays $RetentionTotal})

    }
    #The following else statement is hit when none of the necessary permissions are in place for the change to be made.
    else{
        Write-Output "The Subscription: $Subscription does not contain the appropriate roles to modify the tables. Please review with the customer. "
        #We will add the failed subscription IDs to a array which we will convert to csv format to then export.
        $Fail += $Subscription
        continue
        }

        } -TimeoutSeconds 120 -AsJob 
    }
    #After the for loop has completed we will now convert our array to a different data type. 
   $Fail | ConvertTo-Csv -NoTypeInformation | Set-Content -Path /Failed/SubscriptionsFailed.csv

function RetentionSpecificCust{
    az account list --output table 
    $Subscription = Read-Host "Please enter the subscription context for the customer that you are working with"
    az account set --$Subscription
    
    az group list --query '[].name'
    $ResourceGroups = Read-Host "Please enter the Resource group which contains the Log analytics workspace we will need to edit. "
    
    az monitor log-analytics workspace list --query '[].name'
    WorkspaceName = Read-Host "Please enter the log analytics workspace name that you would like to edit the retention for. "

    $CustReten = Read-Host "Would you like to set a custom retention period outside of the Ntirety Default of 90 days hot & 365 cold. Keep in mind changes outside of this should be vetted with the appropriate teams in regards to cost?
    1. Yes
    2. No"
    if ($CustReten = 1){
        $RetentionDays = Read-Host "What would you like the hot storage to be for this customer?"
        $RetentionTotal = Read-Host "What would you like the cold storage to be for this customer"
    }
    elseif($CustReten = 2){
        continue
    }

    $RetenType = Read-Host "Would you like to edit all of the tables located within the subscription? or just change one specific tables retention setting? 
    1.) Proceed with changing retention for all tables
    2.) Proceed with only modifying a specific table. (Note that if you don't have the exact table name this command will not work.)
    "
    if ($RetenType = 1 ){
        $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceName --query '[].name' --output table )
        $tables.ForEach({
            az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceName --name $table --retention-time $RetentionDays --total-retention-time $RetentionTotal})
    }
        elseif ($RetenType = 2 ){
        $TableName = Read-Host "Please enter the name of the table that you would like to edit. "
        az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceName --name $TableName --retention-time $RetentionDays --total-retention-time $RetentionTotal
    }

    }


## The following function needs to be improved so that we can call the necessary info into the correct format into a CSV file    
#function RetentionAudit{
#   do{
#   $SubsToAudit = Read-Host "Would you like to audit all of the subscriptions or just one? 
#   1.) All Customers
#   2.) Just One Customer subscription
#   3.) Exit to Main menu
#   "
#   ##We will use a hashtable which will hold our Subscription Name and Retention Compliance status.
#   $FailedReten = @()
#
#   
#   
#   }until( $SubsToAudit -eq 1 -or $SubsToAudit -eq 2)
#
#   if($SubsToAudit = 1 ){
#   
#       $Subscriptions = @(az account list --query '[].name')
#
#       ##Declares our array which will house our necessary values 
#       $TableRetenAllCust = @()
#       $CompliantTables
#   #Ensures that this is run against every subscription that we can reach. 
#   foreach ($Subscription in Subscriptions){
#
#   #This line ensures that we are located in the first subscription out of our array that we created.
#   az account set --subscription $Subscriptions
#   az account show --query '[].name'
#   #This will pull the Rgs and pull out only the ones that we created.
#   $ResourceGroups = az group list --query '[].name' | Select-String 'H\d{6}'
#   #The following below should only pull log analytics workspaces that are in line with our naming convention.
#   $WorkspaceNames = az monitor log-analytics workspace list --query '[].name' | Select-String -Pattern 'H\d{6}'
#
#   #Ensures that our workspace name isn't empty & then runs using the Rg & WS name collected above. 
#   if($WorkspaceNames -ne "" ){
#   #Collects the necessary table names which don't have the correct retention settings set.
#   $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query '[].{name:name,totalRetentionInDays:totalRetentionInDays}')| ConvertFrom-Json ` | Select-Object -Property name, totalRetentionInDays ` | Where-Object {$_totalRetentionInDays -le 365}
#   
#    
#
##The below will create a custom object when a customer has tables which fail the check.
#   if($tables -ne ""){
#   $TableRetenAllCust += [pscustomobject]@{
#    SubscriptionID = $Subscription
#    FailedTables = $tables
#    Customer = $WorkspaceNames
#
#            }
#   #Added the elseif so we can create our necessary CSV with customer names in compliance 
#    elseif(-not $tables){
#$CompliantTables += [pscustomobject]@{
#    SubscriptionID = $Subscription
#    Customer = $WorkspaceNames
#}
#          }
#
#        }   
#   #the following will run when the LAW is empty
#        }
#    }
#
## the below will aggregate our failed tables in a csv by customer.   Need to set the path to be relative to where the script is running.
#$TableRetenAllCust | Group-Object Customer | ForEach-Object {
#   $CsvPath = "C:\TableRetenAllCust_$($_.Name).csv"
#   $_.Group | Export-Csv -Path $CsvPath -NoTypeInformation
#}
#CompliantTables | Group-Object Customer | ForEach-Object {
#   $CsvPath = "C:\TableRetenAllCust_$($_.Name).csv"
#   $_.Group | Export-Csv -Path $CsvPath -NoTypeInformation
#}
#
#}
#
#}
### Creates our menu to allow our users to select the necessary utility.
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