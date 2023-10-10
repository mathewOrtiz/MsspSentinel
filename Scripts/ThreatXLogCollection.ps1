# Replace with your Workspace ID
$CustomerId = $env:LogAnalytics

# Replace with your Primary Key
$SharedKey = $env:SharedKey

# Specify the name of the record type that you'll be creating
$LogType = "ThreatX"

# Optional name of a field that includes the timestamp for the data. If the time field is not specified, Azure Monitor assumes the time is the message ingestion time
$TimeStampField = "timestamp"

#We grab the current time this is utilized for the match events this prevents us from collecting to many events.
$StartTime = Get-Date

#This line will need to be removed

$AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=ntiretymsspprodsent84a4;AccountKey=gU5qqj7E6q6Kjij4fpkMlCBi4ghXIPEKmP8+VbPosIrXn1jdD4F49dsQ9Ev8+60x4dVTeuh8kEbn+ASt6KENmw==;EndpointSuffix=core.windows.net"

#Authenticate to ThreatX 
# Define the URI
$UriLogin = 'https://provision.threatx.io/tx_api/v1/login'
$UriLogs = 'https://provision.threatx.io/tx_api/v2/logs'
$ApiKey = $env:ApiKey

#Storage account used for state tracking. 
$TableName = "ThreatX"
# Create the headers
$headers = New-Object "System.Collections.Generic.Dictionary[[string],[string]]"
$headers.Add('Content-Type', 'application/json')

#Define our functions which are related to log shipping to Sentinel. 
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource) {
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId, $encodedHash
    return $authorization
}
Function SentinelLogShip($json) {
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
        "Authorization"        = $signature;
        "Log-Type"             = $logType;
        "x-ms-date"            = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $Laheaders -Body $body -UseBasicParsing
}

function SaveState {
    #We will now check to see if we need to make any table entries before we stop execution. 
    if ($ResponseMatchEvent.Ok.is_complete.ToString() -eq "False") {
        $result = Add-AzTableRow -table $Table -PartitionKey "MatchEvent" -RowKey "ResumePoint" -property @{"last_seen" = $ResponseMatchEvent.Ok.last_seen_key.timestamp.ToString("yyyy-MM-dd'T'HH:mm:ss.fffK") } -UpdateExisting
    }
    if ($ResponseBlockEvent.Ok.is_complete.ToString() -eq "False") {
        $result = Add-AzTableRow -table $Table -PartitionKey "BlockEvent" -RowKey "ResumePoint" -Property @{"last_seen" = $ResponseBlockEvent.Ok.last_seen_key.timestamp.ToString("yyyy-MM-dd'T'HH:mm:ss.fffK") } -UpdateExisting
    }
    if ($ResponseAuditEvent.Ok.is_complete.ToString() -eq "False") {
        $result = Add-AzTableRow -table $Table -PartitionKey "AuditEvent" -RowKey "ResumePoint" -Property @{"last_seen" = $ResponseAuditEvent.Ok.last_seen_key.timestamp.ToString("yyyy-MM-dd'T'HH:mm:ss.fffK") } -UpdateExisting
    }
    #We now exit our script and we will continue with the above saved start times on our next run. 
    break
}

function FetchToken {
    #End the script prep work and being the log fetching process. 
    $body = @{
        command   = 'login'
        api_token = $ApiKey
    } | ConvertTo-Json

    # Make the request and store the token for use later on during our loop for request. We declare as global so that we can utilize this later. 
    $Global:ApiToken = Invoke-RestMethod -Uri $UriLogin -Method Post -Headers $headers -Body $body
    $Global:ApiToken.Ok.token
}

#We check our table for any stored values that need to be fetched. 
function StateFetch {
    $storage = New-AzStorageContext -ConnectionString $AzureWebJobsStorage
    $StorageTable = Get-AzStorageTable -Name $Tablename -Context $Storage -ErrorAction Ignore
    if ($null -eq $StorageTable.Name) {  
        $result = New-AzStorageTable -Name $Tablename -Context $storage
        $Table = (Get-AzStorageTable -Name $Tablename -Context $storage.Context).cloudTable
        $result = Add-AzTableRow -table $Table -PartitionKey "match" -RowKey "TimeResume" -property @{"TimeStamp" = $StartTime } -UpdateExisting
        $result = Add-AzTableRow -table $Table -PartitionKey "block" -RowKey "TimeResume" -property @{"TimeStamp" = $StartTime } -UpdateExisting
        $result = Add-AzTableRow -table $Table -PartitionKey "audit" -RowKey "TimeResume" -property @{"TimeStamp" = $StartTime } -UpdateExisting
        RetrieveLogs
    }
    Else {
        $Table = (Get-AzStorageTable -Name $Tablename -Context $storage.Context).cloudTable
    }

    #We look for the match events first.
    $row = (Get-AzTableRow -table $Table -PartitionKey "match" -RowKey "TimeResume")
    if ($null -ne $row.TimeStamp) {
        $ResumeMatch = Get-AzTableRow -table $Table -PartitionKey "match" -RowKey "TimeResume" -ErrorAction Ignore
        #Create our JSON body & send the request. We create a global variable which can be read after this in order to continue fetching request. 
        $BodyMatchEvents = @{
            command       = "match_events"
            token         = $Global:ApiToken.Ok.token
            customer_name = $env:CustomerName
            start_after   = $ResumeMatch.TimeResume
            limit         = 1000
        } | ConvertTo-Json
        #Now that we have our JSON body created we work on forwarding the request & creating our global value.
        $Global:ResponseMatchEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyMatchEvents -Headers $headers
    }
    #Check our Block events
    $row = (Get-AzTableRow -table $Table -PartitionKey "block" -RowKey "TimeResume")
    if ($null -ne $row.TimeStamp) {
        $ResumeBlock = Get-AzTableRow -table $Table -PartitionKey "block" -RowKey "TimeResume" -ErrorAction Ignore
        $BodyBlockEvents = @{
            command       = "block_events"
            token         = $Global:ApiToken.Ok.token
            customer_name = $env:CustomerName
            start_after   = $ResumeBlock.TimeResume
            limit         = 1000
        } | ConvertTo-Json
        $Global:ResponseBlockEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyBlockEvents -Headers $headers
    }
    #Check for our audit events.
    $row = (Get-AzTableRow -table $Table -PartitionKey "audit" -RowKey "TimeResume")
    if ($null -ne $row.TimeStamp) {
        $ResumeAudit = Get-AzTableRow -table $Table -PartitionKey "audit" -RowKey "TimeResume" -ErrorAction Ignore
        $BodyAuditEvent = [ordered]@{
            command       = "audit_events"
            token         = $ApiToken.Ok.token
            customer_name = $env:CustomerName
            start_after   = $ResumeAudit.TimeResume
            limit         = 1000
        } | ConvertTo-Json
        $Global:ResponseAuditEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyAuditEvent -Headers $headers
    }

    $PopulatedCount = 0 
    #Depending on the necessary configuration we will now work to ship the necessary logs and then run those logs further.
    if ($null -ne $Global:ResponseMatchEvent) { $PopulatedCount++ }
    if ($null -ne $Global:ResponseBlockEvent) { $PopulatedCount++ }
    if ($null -ne $Global:ResponseAuditEvent) { $PopulatedCount++ }

    switch ($PopulatedCount) {
        3 {
            #All three variables are populated we now forward all three events
            $JsonMatchEvents = ConvertTo-Json $Global:ResponseMatchEvent -Depth 10
            $JsonBlockEvents = ConvertTo-Json $Global:ResponseBlockEvent -Depth 10
            $JsonAuditEvents = ConvertTo-Json $Global:ResponseAuditEvent -Depth 10
            SentinelLogShip -json $JsonMatchEvents
            SentinelLogShip -json $JsonBlockEvents
            SentinelLogShip -json $JsonAuditEvents

            wait 10
            RetrieveLogs -ResponseMatchEvent $Global:ResponseMatchEvent -ResponseBlockEvent $Global:ResponseBlockEvent -ResponseAuditEvent $Global:ResponseAuditEvent
        }
        2 {
            #If only the Match & Block event are populated we will check and grab their logs
            $JsonMatchEvents = ConvertTo-Json $Global:ResponseMatchEvent -Depth 10
            $JsonBlockEvents = ConvertTo-Json $Global:ResponseBlockEvent -Depth 10
            SentinelLogShip -json $JsonMatchEvents
            SentinelLogShip -json $JsonBlockEvents

            #pause and then continue on our to our main loop passing the necessary values from the previous run
            wait 10
            RetrieveLogs -ResponseMatchEvent $Global:ResponseMatchEvent -ResponseBlockEvent $Global:ResponseBlockEvent
        }
        1 {
            $JsonMatchEvents = ConvertTo-Json $Global:ResponseMatchEvent -Depth 10
            SentinelLogShip -json $JsonMatchEvents

            wait 10
            RetrieveLogs -ResponseMatchEvent $Global:ResponseMatchEvent
        }
        default {
            #We didn't have any log messages to collect from our last run we will now fetch all our previous logs.
            RetrieveLogs
        }
    }
    #Ensure that we deliver these log messages to the necessary location via a conversion of the data & calling our log ship function. 
    $JsonMatchEvents = ConvertTo-Json $ResponseMatchEvent -Depth 10
    $JsonBlockEvents = ConvertTo-Json $ResponseBlockEvent -Depth 10
    $JsonAuditEvents = ConvertTo-Json $ResponseAuditEvent -Depth 10
    SentinelLogShip -json $JsonMatchEvents
    SentinelLogShip -json $JsonBlockEvents
    SentinelLogShip -json $JsonAuditEvents

    wait 10
    #After collecting our variables we will now go ahead and kick off our main loop. This loop functions by providing the necessary values via params.
    RetrieveLogs -ResponseAuditEvent $ResponseAuditEvent -ResponseBlockEvent $ResponseBlockEvent -ResponseMatchEvent $ResponseMatchEvent
    #This our main loop we will utilize the previous values that we have gained from the resposne sent from our stateful check. 
}
Function RetrieveLogs($ResponseAuditEvent, $ResponseMatchEvent, $ResponseBlockEvent) {
    <#
.SYNOPSIS
Forwards the necessary logs to the log analytics workspace. This uses the older API endpoint which does dynamic schema generation. This will need to be update to the DCR based method eventually.

.DESCRIPTION
This function will loop through our ThreatX log messages. This loop is started at two different points potentially. If we have a stateful value which is being passed in by the StateFetch function we start at the last seen from our previous script execution run. If we didn't find any values from our statefulness check we proceed to start pulling logs from our current run time. 

.PARAMETER ResponseAuditEvent
This contains the response body from our statefulness check script. 

.PARAMETER ResponseMatchEvent
This contains the response body for the match events log endpoint. 

.PARAMETER ResponseBlockEvent
This contains the response body for the block event log endpoint.

.EXAMPLE
An example

.NOTES
General notes
#>

    $PopulatedCount
    do {
        #Checks to see if all the match request have been fetched from the last run. If not it will go ahead and create a new body which will take this into account. 
        if ($ResponseMatchEvent.Ok.is_complete -eq $false) {
            Write-Host "There are still events which need to be collected we will grab those now. "
            $BodyMatchEvents = @{
                command       = "match_events"
                token         = $Global:ApiToken.Ok.token
                customer_name = $env:CustomerName
                start_after   = $Global:ResponseMatchEvent.Ok.last_seen_key
                limit         = 1000
            } | ConvertTo-Json

            #Creates our request body in without the start_after property because this is a fresh run or we are all caught up on records. 
        }
        else {
            $BodyMatchEvents = @{
                command       = "match_events"
                token         = $Global:ApiToken.Ok.token
                time_start    = $StartTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffK")
                customer_name = $env:CustomerName
                limit         = 1000
            } | ConvertTo-Json
        }
    
        if ($Global:ResponseBlockEvent.Ok.is_complete -eq $false) {
            Write-Host "There are still Block events which need to be collected from the last run. We will start collecting from this last point. "
            $BodyBlockEvents = @{
                command       = "block_events"
                token         = $Global:ApiToken.Ok.token
                customer_name = $env:CustomerName
                start_after   = $Global:ResponseBlockEvent.Ok.last_seen_key
                limit         = 1000
            } | ConvertTo-Json
    
        }
        else {
            #Creates our body for the block event fetch. 
            $BodyBlockEvents = @{
                command       = "block_events"
                token         = $Global:ApiToken.Ok.token
                customer_name = $env:CustomerName
                time_start    = $StartTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffK")
                limit         = 1000
            } | ConvertTo-Json
        }

        if ($Global:ResponseAuditEvent.Ok.is_complete -eq $false) {
            Write-Host "There are still Audit events which need to be collected from the last run. We will start collecting from this last point. "
            $BodyAuditEvent = [ordered]@{
                command       = "audit_events"
                token         = $ApiToken.Ok.token
                customer_name = $env:CustomerName
                start_after   = $Global:ResponseAuditEvent.Ok.last_seen_key
                limit         = 1000
            } | ConvertTo-Json
        }
        else {
            #Creates our body for the block event fetch. 
            $BodyAuditEvent = @{
                command       = "audit_events"
                token         = $ApiToken.Ok.token
                customer_name = $env:CustomerName
                start_time    = $StartTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffK")
                limit         = 1000
            } | ConvertTo-Json
        }
        
        #Retrieves the match events that have been seen by ThreatX. 
        $ResponseMatchEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyMatchEvents -Headers $headers
        #Retrieves the block events that have been seen. Depending on the status of the if statement this will start from the beginning of the day or from the last log message recorded. 
        $ResponseBlockEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyBlockEvents -Headers $headers
        #Retrieves the audit event logs that have been generated. This will allow us to monitor and track historic changes.
        $ResponseAuditEvent = Invoke-RestMethod -Uri $UriLogs -Method Post -Body $BodyAuditEvent -Headers $headers
        
        #This is a test scenario
        Write-Host "The response match event will be printed out here"
        $ResponseMatchEvent
        Write-Host "The response block event will be printed out here"
        $ResponseBlockEvent
        Write-Host "The response audit event will be printed out here"
        $ResponseAuditEvent

        $BodyMatchEvents
        $BodyBlockEvents
        $BodyAuditEvent

        $ElapsedTime
        Read-Host "Wato to continue?"
        #Prepare our data to be sent to Sentinel. 
        $ParsedMatchEvent = ConvertTo-Json -Depth 10  $ResponseMatchEvent.Ok.data   
        $ParsedBlockEvent = ConvertTo-Json -Depth 10  $ResponseBlockEvent.Ok.data
        $ParsedAuditEvent = ConvertTo-Json -Depth 10  $ResponseAuditEvent.Ok.data

        SentinelLogShip -json $ParsedMatchEvent
        SentinelLogShip -json $ParsedBlockEvent
        SentinelLogShip -json $ParsedAuditEvent

        #Check the amount of time that we have been running for so we gracefully exit before 10 minutes.
        $CurrentTime = Get-Date
        $ElapsedTime = ($CurrentTime - $StartTime).TotalMinutes
        if ($ElapsedTime -ge 9) {
            SaveState
        }

        #Check our response data to see if we need to keep the loop going. We do this by verifying that all of the 
    }while ($ResponseMatchEvent.Ok.is_complete.ToString() -eq "False" -or $ResponseBlockEvent.Ok.is_complete.ToString() -eq "False" -or $ResponseAuditEvent.Ok.is_complete.ToString() -eq "False")
}
#IF((new-timespan -Start $currentUTCtime -end ((Get-Date).ToUniversalTime())).TotalSeconds -gt 500){$DoUntil = $true}
FetchToken
StateFetch