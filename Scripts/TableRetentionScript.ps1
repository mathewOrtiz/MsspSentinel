$RetentionDays = 90
$RetentionTotal = 365

##Uncomment the below lines in order to have table retention set for all subscriptions to something different then the default 

#$RetentionDays = Read-Host "What is the total amount of days that you would like to have hot storage available to you? "
#$RetentionTotal = Read-Host "What is the total amount of time that you would like your retention configured for? This will be the amount of time to retain archival logs. "

#Creates a array with all of the subscriptions. The output variable is needed in order to ensure that the formatting is correct
$Subscriptions = @(az account list --query '[].id' --output tsv)

#Ensures that this is run against every subscription that we can reach. 
    foreach ($Subscription in $Subscriptions){
    Start-Job{
    #Collects our resource groups from each subscription and will associate itself with the resource group variable. 
    az account set --subscription $Subscription
    #queries our current subscription to ensure that we have the necessary role to make the table updates. 
    $Perms = az role assignment list --query '[].roleDefinitionName' --output table | Select-String -Pattern "Log Analytics Contributor"
    Write-Output $Perms
    
    #the following below is added in to make sure that we only attempt to run the commands on subs where we are able to.
    if($Perms -like "*Log*"){

        $ResourceGroups = az group list --query '[].name' --output table | Select-String 'AzureSentinel'
        $WorkspaceNames = az monitor log-analytics workspace list --query '[].name' --output table | Select-String 'AzureSentinel'
        #Collects the necessary table names. This specifically queries only the names of the tables & ensures that we don't return any additional formatting just raw strings.
        $tables = @(az monitor log-analytics workspace table list --resource-group $ResourceGroups --workspace-name $WorkspaceNames --query '[].name' --output table)
        Write-Output $tables

        #the following will actually work through every table in the list to modify the retention that is set to meet our standards.
        foreach($table in $tables){
        Write-Output "For Loop hit"
        az monitor log-analytics workspace table update --resource-group $ResourceGroups --workspace-name $WorkspaceNames --name $table --retention-time $RetentionDays --total-retention-time $RetentionTotal
        Write-Output "Table reten updated"
    }
    }

    #The following else statement is hit when none of the necessary permissions are in place for the change to be made.
    else{
        Write-Output "else statement hit"
        continue
    }

} -ArgumentList $Subscription -Name $Subscription
    
}