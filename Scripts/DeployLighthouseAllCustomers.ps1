$HomeTenantId = "984cdaad-80ea-4659-a39b-0a3b3f0c7bfb" #Ntirety main tenant
Connect-AzAccount -TenantId $HomeTenantId -WarningAction Ignore | Out-Null

$LighthouseRoles = @(
    #Roles for Security Engineering
	@{
		searchName = "Security Engineering"
		displayName = "Security Engineer"
		roles = @(
			'Microsoft Sentinel Contributor',
			'Azure Connected Machine Resource Administrator',
			'Monitoring Contributor',
			'Tag Contributor',
			'Classic Virtual Machine Contributor',
			'Resource Policy Contributor',
			'Managed Identity Contributor',
			'Key Vault Contributor',
			'Storage Account Contributor',
			'Log Analytics Contributor',
			'Logic App Contributor',
			'Template Spec Contributor',
			'User Access Administrator'
		)
	}
    #Roles for Security Analysts
	@{
		searchName = "Security Analyst"
		displayName = "Security Analyst" 
		roles = @(
			'Microsoft Sentinel Responder',
			'Log Analytics Reader',
			'Microsoft Sentinel Playbook Operator'
		)
	}
	#Roles for SOC Contributors
	@{
		searchName = "SentinelContributors"
		displayName = "SOC Contributors" 
		roles = @(
			'Microsoft Sentinel Contributor',
			'Log Analytics Reader',
			'Microsoft Sentinel Playbook Operator'
		)
	}
    #Roles for SOC Readers
	@{
		searchName = "SentinelReaders"
		displayName = "SOC Readers" 
		roles = @(
			'Reader'
		)
	}
    #Roles for Automation Service Principals
	@{
		searchName = "Automation"
		displayName = "Automation" 
		roles = @(
			'Microsoft Sentinel Responder'
		)
	}
)

#Roles assignable by users with the User Access Administrator role
$UserAccessDelegatedRoles = @(
	'Azure Connected Machine Onboarding',
	'Hybrid Server Onboarding',
	'Kubernetes Cluster - Azure Arc Onboarding',
	'Monitoring Metrics Publisher'
)

#Build the parameters for the Lighthouse connection
function BuildLighthouseParameters{
    [CmdletBinding()]
    param (
		[Parameter (Mandatory = $true)]
        [string]
        $HomeTenantId,

        [Parameter (Mandatory = $true)]
        [array]
        $LighthouseRoles,

		[Parameter (Mandatory = $false)]
        [array]
        $UserAccessAdminRoles
    )

	$LighthouseRolesTemplate = @()
	$RequiredRoles = @()

	foreach ($team in $LighthouseRoles)
	{
		foreach ($role in $team.roles)
		{
			if($role -eq 'User Access Administrator'){
				$delegatedRoleDefinitionIds = @()

				foreach ($assignableRole in $UserAccessDelegatedRoles)
				{
					$delegatedRoleDefinitionIds += (Get-AzRoleDefinition -Name $assignableRole).Id
				}

				$LighthouseRolesTemplate += @{
					delegatedRoleDefinitionIds = $delegatedRoleDefinitionIds
					principalId = (Get-AzADGroup -SearchString $team.searchName).Id
					principalIdDisplayName = $team.displayName
					roleDefinitionId = (Get-AzRoleDefinition -Name $role).Id
				}
				$RequiredRoles += [ordered]@{
					DelegatedRoleDefinitionId = $delegatedRoleDefinitionIds
					PrincipalId = (Get-AzADGroup -SearchString $team.searchName).Id
					PrincipalIdDisplayName = $team.displayName
					RoleDefinitionId = (Get-AzRoleDefinition -Name $role).Id
				}
			}
			else{
				$LighthouseRolesTemplate += @{
						principalId = (Get-AzADGroup -SearchString $team.searchName).Id
						principalIdDisplayName = $team.displayName
						roleDefinitionId = (Get-AzRoleDefinition -Name $role).Id
					}
				$RequiredRoles += [ordered]@{
					DelegatedRoleDefinitionId = $null
					PrincipalId = (Get-AzADGroup -SearchString $team.searchName).Id
					PrincipalIdDisplayName = $team.displayName
					RoleDefinitionId = (Get-AzRoleDefinition -Name $role).Id
				}
			}
		}
	}

    $templateParameters = [ordered]@{
        mspOfferName = "Ntirety Lighthouse SOC"
        mspOfferDescription = "Ntirety SOC access granted"
        managedByTenantId = $HomeTenantId
        authorizations = $LighthouseRolesTemplate
    }

    return $templateParameters, ($RequiredRoles | ConvertTo-Json)
}   

Write-Host "Building Lighthouse template parameters"
Set-AzContext -Tenant $HomeTenantId -WarningAction Ignore | Out-Null
$TemplateParameters, $RequiredAuthorizations = BuildLighthouseParameters -HomeTenantId $HomeTenantId -LighthouseRoles $LighthouseRoles -UserAccessAdminRoles $UserAccessDelegatedRoles
$LighthouseTemplate = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/Azure-Lighthouse-samples/master/templates/delegated-resource-management/subscription/subscription.json).Content | ConvertFrom-Json -AsHashtable
$query = "resources
			| where type =~ 'microsoft.operationalinsights/workspaces'
			| extend  workspaceId = properties.customerId, production = tags.Production
			| where production == 'True' or name == 'H228100'
			| project name, workspaceId, resourceGroup, subscriptionId, tenantId, location"

$Customers = Search-AzGraph -Query $query -First 1000 -Skip 60

$VerifiedSubs = @()
$SuccessSubs = @()
$ErrorSubs = @()

try {
	ForEach ($Customer in $Customers){
		$PSStyle.Progress.MaxWidth = 100
		$psstyle.Progress.Style = "`e[38;5;42m" #green
		$perc =  [math]::Round(($Customers.IndexOf($Customer) / $Customers.count) * 100)
		Write-Progress -Activity "  $perc% complete" -Status "Establishing Azure Lighthouse connection to $($Customer.name)" -PercentComplete $perc

		#Connect to customer tenant
		$error.clear()
		if($Customer.name -ne 'H225931AzureSentinel')
		{
			Write-Progress -Activity "  $perc% complete" -Status "Connecting to $($Customer.name)" -PercentComplete $perc
			Connect-AzAccount -TenantId $Customer.tenantId -SubscriptionId $Customer.subscriptionId -WarningAction Ignore -ErrorAction SilentlyContinue | Out-Null
			Start-Sleep -s 15
		}

		if($error){
			#Write-Host "Error connecting to $($Customer.name)"
			Write-Progress -Activity "  $perc% complete" -Status "Error connecting to $($Customer.name)" -PercentComplete $perc
			$ErrorSubs += [ordered]@{
				Customer = $Customer.name
				Subscription = $Customer.subscriptionId
				ErrorType = "Authentication"
				Error = $error[0]
			}
		}
		else{
			#Write-Host "Getting current service offering roles for $($Customer.name)..."
			Write-Progress -Activity "  $perc% complete" -Status "Getting current service offering roles for $($Customer.name)" -PercentComplete $perc
			$CurrentAuthorizations = (Get-AzManagedServicesDefinition -WarningAction Ignore -ErrorAction SilentlyContinue | Where-Object {$_.RegistrationDefinitionName -eq 'Ntirety Lighthouse SOC'}).Authorization | ConvertTo-Json

			if($CurrentAuthorizations -ne $RequiredAuthorizations)
			{
				#Write-Host "--Current roles do not match required roles. Deploying latest service offering to $($Customer.name)."
				Write-Progress -Activity "  $perc% complete" -Status "Missing roles. Deploying latest service offering to $($Customer.name)" -PercentComplete $perc
				$error.clear()
				New-AzDeployment -TemplateParameterObject $TemplateParameters -TemplateObject $LighthouseTemplate -Location $Customer.location -ErrorAction SilentlyContinue | Out-Null

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
				#Write-Host "--$($Customer.name) already has the most up to date service offering roles"
				Write-Progress -Activity "  $perc% complete" -Status "$($Customer.name) has all the required roles" -PercentComplete $perc
				$VerifiedSubs += $Customer.name
			}
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