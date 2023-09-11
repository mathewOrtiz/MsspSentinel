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
$UriLogin = 'https://provision.threatx.io/tx_api/v1/login'
$UriLogs = 'https://provision.threatx.io/tx_api/v2/logs'
$ApiKey = $env:ApiKey

#Storage account used for state tracking. 
$AzureWebJobsStorage = $env:AzureWebJobsStorage
$TableName = "ThreatX"
$storage = New-AzStorageContext -ConnectionString $AzureWebJobsStorage
$StorageTable = Get-AzStorageTable -Name $TableName -Context $storage -ErrorAction Ignore
if($null -eq $StorageTable.Name){
    $result = New-AzStorageTable -Name $TableName -Context $storage
    $table = (Get-AzStorageTable -Name $TableName -Context $storage.Context).cloudTable
}


# Create the headers
$headers = New-Object "System.Collections.Generic.Dictionary[[string],[string]]"
$headers.Add('Content-Type', 'application/json')

#Define our functions which are related to log shipping to Sentinel. 
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
Function SentinelLogShip($json){
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
}

#End the script prep work and being the log fetching process. 



    $body = @{
        command = 'login'
        api_token = $ApiKey
    } | ConvertTo-Json

    # Make the request and store the token for use later on during our loop for request. We declare as global so that we can utilize this later. 
    $Global:ApiToken = Invoke-RestMethod -Uri $UriLogin -Method Post -Headers $headers -Body $body
    $Global:ApiToken.Ok.token


$DoUntil = $false
#Use this to record the last request that is made. If the Content is empty then we will right this to the table so we can start the queries again.
$TimeStamp = $LoopMarker.Ok.last_seen_key.Timestamp

#Storage table creation and check .
$storage =  New-AzStorageContext -ConnectionString $AzureWebJobsStorage
$StorageTable = Get-AzStorageTable -Name $Tablename -Context $Storage -ErrorAction Ignore
if($null -eq $StorageTable.Name){  
    $result = New-AzStorageTable -Name $Tablename -Context $storage
    $Table = (Get-AzStorageTable -Name $Tablename -Context $storage.Context).cloudTable
    $result = Add-AzTableRow -table $Table -PartitionKey "part1" -RowKey $Global:ApiToken.Ok.token -property @{"TimeStamp"=$TimeStamp} -UpdateExisting
}
Else {
    $Table = (Get-AzStorageTable -Name $Tablename -Context $storage.Context).cloudTable
}
# retrieve the row
$row = Get-azTableRow -table $Table -partitionKey "part1" -RowKey $Global:ApiToken -ErrorAction Ignore
if($null -eq $row.TimeStamp){
    $result = Add-AzTableRow -table $Table -PartitionKey "part1" -RowKey $Global:ApiToken.Ok.token -property @{"TimeStamp"=$TimeStamp} -UpdateExisting
    $row = Get-azTableRow -table $Table -partitionKey "part1" -RowKey $Global:ApiToken.Ok.token -ErrorAction Ignore
}


do{
#Checks to see if all the match request have been fetched from the last run. If not it will go ahead and create a new body which will take this into account. 
if($ResponseMatchEvent.Ok.is_complete -ne $true){
    Write-Host "There are still events which need to be collected we will grab those now. "
    $BodyMatchEvents = @{
        command = "match_events"
        token = $Global:ApiToken.Ok.token
        customer_name = "ntirety"
        start_after = $ResponseMatchEvent.Ok.last_seen_key
        limit = 1000
    } | ConvertTo-Json

#Creates our request body in without the start_after property because this is a fresh run or we are all caught up on records. 
}else{
        $BodyMatchEvents = @{
            command = "match_events"
            token = $Global:ApiToken.Ok.token
            customer_name = "ntirety"
            limit = 1000
        } | ConvertTo-Json
    }

if($ResponseBlockEvent.Ok.is_complete -ne $true){
    Write-Host "There are still events which need to be collected from the last run. We will start collecting from this last point. "
    $BodyBlockEvents = @{
        command = "block_events"
        token = $Global:ApiToken.Ok.token
        customer_name = "ntirety"
        start_after = $ResponseBlockEvent.Ok.last_seen_key
        limit = 1000
    } | ConvertTo-Json
    
}elseif($null -eq $ResponseBlockEvent.Ok.is_complete){
#Creates our body for the block event fetch. 
    $BodyBlockEvents = @{
        command = "block_events"
        token = $Global:ApiToken.Ok.token
        customer_name = "ntirety"
        limit = 1000
} | ConvertTo-Json
}

#Creates
if($ResponseAuditEvent.Ok.is_complete -ne $true){
    Write-Host "There are still events which need to be collected from the last run. We will start collecting from this last point. "
    $BodyAuditEvent = @{
        command = "audit_events"
        token = $ApiToken.Ok.token
        customer_name = "ntirety"
        start_after = $ResponseBlockEvent.Ok.last_seen_key
        limit = 1000
    } | ConvertTo-Json
    
}else{
#Creates our body for the block event fetch. 
    $BodyAuditEvent = @{
        command = "audit_events"
        token = $ApiToken.Ok.token
        customer_name = "ntirety"
        limit = 1000
} | ConvertTo-Json
}

$BodyMatchEvents
$BodyBlockEvents
$BodyAuditEvent

#Retrieves the match events that have been seen by ThreatX. 
$ResponseMatchEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyMatchEvents -Headers $headers

#Retrieves the block events that have been seen. Depending on the status of the if statement this will start from the beginning of the day or from the last log message recorded. 
$ResponseBlockEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyBlockEvents -Headers $headers

#Retrieves the audit event logs that have been generated. This will allow us to monitor and track historic changes.
$ResponseAuditEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyAuditEvent -Headers $headers


#Prepare our data to be sent to Sentinel. 
$ParsedMatchEvent =  ConvertTo-Json -Depth 10   $ResponseMatchEvent.Ok.data   
$ParsedBlockEvent =  ConvertTo-Json -Depth 10   $ResponseBlockEvent.Ok.data
$ParsedAuditEvent =  ConvertTo-Json -Depth 10   $ResponseAuditEvent.Ok.data

$ParsedMatchEvent
SentinelLogShip -json $ParsedMatchEvent
SentinelLogShip -json $ParsedBlockEvent
SentinelLogShip -json $ParsedAuditEvent
#Check our response data to see if we need to keep the loop going. We do this by verifying that all of the 
}while($ResponseMatchEvent.Ok.is_complete -ne $false -or $ResponseBlockEvent.Ok.is_complete -ne $false -or $ResponseAuditEvent.Ok.data -ne $false)

#Now we need to write our timestamp to the table. We do this by fetching the last timestamp
$LastSeen = $response.Ok.last_seen_key.request_id


#Once we have exited our loop we right the last seen request_id to the table we created. This ensures on the next run that we are able to record this record as well. 
$result = Add-AzTableRow -table $Table -PartitionKey "part1" -RowKey $Global:ApiToken -property @{"last_seen"=$LastSeen} -UpdateExisting



IF((new-timespan -Start $currentUTCtime -end ((Get-Date).ToUniversalTime())).TotalSeconds -gt 500){$DoUntil = $true}
GetApiToken