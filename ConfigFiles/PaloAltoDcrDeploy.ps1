#Used to ensure that the user is not in the context of the customer

Connect-AzAccount -Tenant 
$Subscriptions = @((Get-AzSubscription).Id)
 #Need to grab our JSON config file from Github then modify with .notation

 #Begin our loop
