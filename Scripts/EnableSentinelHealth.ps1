$HomeTenantId = "984cdaad-80ea-4659-a39b-0a3b3f0c7bfb" #Ntirety main tenant
Connect-AzAccount -TenantId $HomeTenantId -WarningAction Ignore | Out-Null
Set-AzContext -Tenant $HomeTenantId -WarningAction Ignore | Out-Null

$query = "resources
			| where type =~ 'microsoft.operationalinsights/workspaces'
			| extend  workspaceId = properties.customerId, production = tags.Production
			| where production == 'True' or name == 'H228100'
			| project name, workspaceId, resourceGroup, subscriptionId, tenantId, location, id"

$Customers = Search-AzGraph -Query $query -First 1000

$VerifiedSubs = @()
$SuccessSubs = @()
$ErrorSubs = @()

$metric = @()
$log = @()
$log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -categoryGroup allLogs -RetentionPolicyDay 0 -RetentionPolicyEnabled $false

try {
	ForEach ($Customer in $Customers){
		$PSStyle.Progress.MaxWidth = 100
		$psstyle.Progress.Style = "`e[38;5;42m" #green
		$perc =  [math]::Round(($Customers.IndexOf($Customer) / $Customers.count) * 100)

		$error.clear()

		Write-Progress -Activity "  $perc% complete" -Status "Getting current diagnostic settings for $($Customer.name)" -PercentComplete $perc
		$resourceId = $Customer.id + '/providers/Microsoft.SecurityInsights/settings/SentinelHealth/'
		$currentSettings = Get-AzDiagnosticSetting -ResourceId $resourceId
		$categoryGroup = $currentSettings.Log.CategoryGroup
		$status = $currentSettings.Log.Enabled

		if($categoryGroup -ne "allLogs" -or $status -ne $true)
		{
			Write-Progress -Activity "  $perc% complete" -Status "Enabling Sentinel health and auditing for $($Customer.name)" -PercentComplete $perc
			$error.clear()

			New-AzDiagnosticSetting -Name SentinelAllLogs -ResourceId $resourceId -WorkspaceId $Customer.id -Log $log -Metric $metric -WarningAction Ignore -ErrorAction SilentlyContinue | Out-Null

			if($error){			
				Write-Host "--Error deploying to $($Customer.name)"
				$ErrorSubs += [ordered]@{
					Customer = $Customer.name
					Tenant = $Customer.tenantId
					Subscription = $Customer.subscriptionId
					ErrorType = "Deployment"
					Error = $error[0]
				}
			}
			else{
				$SuccessSubs += $Customer.name
			}
		}
		else{
			Write-Progress -Activity "  $perc% complete" -Status "$($Customer.name) already enabled" -PercentComplete $perc
			$VerifiedSubs += $Customer.name
		}
	}
}
finally {
	if($VerifiedSubs.count -gt 0){
		Write-Host "`n---------- Verified Subscriptions ----------" -ForegroundColor Green
		$VerifiedSubs.ForEach({Write-Host $_})
	}

	if($SuccessSubs.count -gt 0){
		Write-Host "`n---------- Successful Subscriptions ----------" -ForegroundColor Yellow
		$SuccessSubs.ForEach({Write-Host $_})
	}

	if($ErrorSubs.count -gt 0){
		Write-Host "`n---------- Failed Subscriptions ----------" -ForegroundColor Red
		$ErrorSubs.foreach({Write-Host ("Customer:`t{0}`nSubscription:`t{1}`nErrorType:`t{2}`nError:`t`t{3}`n" -f $_["Customer"] , $_["Subscription"], $_["ErrorType"], $_["Error"])})
	}
}