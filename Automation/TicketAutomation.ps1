using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$ArmId = $Request.Query.ArmId

$body = "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response."

if ($ArmId) {
    $SplitId = $ArmId -split "/"
    $SubscriptionId = $SplitId[2]
    #$SubscriptionId = "83ec96f5-9843-4be8-a002-9894e0854ffa"
    $ResourceGroup = $SplitId[4]
    $Workspace = $SplitId[8]
    $IncidentId = $SplitId[12]

    Set-AzContext -Subscription $SubscriptionId
    $Context = Get-AzContext
    #$Results = (Get-AzSentinelIncident -ResourceGroupName $ResourceGroup -workspaceName $Workspace -Id $IncidentId)
    $body = $Context
    #$body = "Sub: " + $Sub + ", Resource Group: " + $ResourceGroup + ", Workspace: " + $Workspace + ", Incident ID: " + $IncidentId
    #$body = (Get-Module -ListAvailable | Select-Object Name)
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
