# Replace with your Workspace ID
$CustomerId = $env:LogAnalytics  

# Replace with your Primary Key
$SharedKey = $env:SharedKey

# Specify the name of the record type that you'll be creating
$LogType = "ThreatX"

# Optional name of a field that includes the timestamp for the data. If the time field is not specified, Azure Monitor assumes the time is the message ingestion time
$TimeStampField = "timestamp"

#Authenticate to ThreatX 
# Define the URI
$uri = 'https://provision.threatx.io/tx_api/v1/login'
$ApiKey = $env:$ApiKey

#Storage account used for state tracking. 
$AzureWebJobsStorage = $env:AzureWebJobsStorage
$TableName = "ThreatX"
$totalRecordCount = 0

$storage = New-AzStorageContext -ConnectionString $AzureWebJobsStorage
$StorageTable = Get-AzStorageTable -Name $TableName -Context $storage -ErrorAction Ignore
if($null -eq $StorageTable.Name){
    $result = New-AzStorageTable -Name $TableName -Context $storage
    $table = (Get-AzStorageTable -Name $TableName -Context $storage.Context).cloudTable
}
# Create the headers
$headers = New-Object "System.Collections.Generic.Dictionary[[string],[string]]"
$headers.Add('Content-Type', 'application/json')

# Create the body as a JSON string
$body = @{
    command = 'login'
    api_token = $ApiKey
} | ConvertTo-Json

# Make the request
$ApiToken= Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body

#Utilize the ApiToken fetched above for the ingestion of the logs.
$uri = "https://provision.threatx.io/tx_api/v2/logs"
$body = @{
    command = "match_events"
    token = $ApiToken.Ok.token
    customer_name = $env:CustName
    limit = 1000
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -Headers $headers

#Used to provide us with a tally of how much data was collected in the last run of the function app. 
$responseCount = $response.Ok.data.count
$TotalRecordCount = $TotalRecordCount + $responseCount

#create our JSON body payload to be sent to Sentinel
$json = $response.Ok.data | ConvertTo-Json -Depth 10 

# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}
# This will post our data to the Sentinel instance using the inbuilt azure monitor data api.
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $body = ([System.Text.Encoding]::UTF8.GetBytes($json))
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $Laheaders = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $Laheaders -Body $body -UseBasicParsing
    return $response.StatusCode
