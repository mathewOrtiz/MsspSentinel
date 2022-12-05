﻿[String[]]$tables = "AADManagedIdentitySignInLogs","AADNonInteractiveUserSignInLogs","AADServicePrincipalSignInLogs","Alert","AlertEvidence","AlertInfo","Anomalies","AppCenterError","ASimDnsActivityLogs","AuditLogs","AWSCloudTrail","AWSGuardDuty","AWSVPCFlow","AzureActivity","AzureDiagnostics","AzureMetrics","BehaviorAnalytics","CloudAppEvents","CommonSecurityLog","ComputerGroup","ConfidentialWatchlist","ConfigurationChange","ConfigurationData","ContainerImageInventory","ContainerInventory","ContainerLog","ContainerNodeInventory","ContainerServiceLog","DeviceEvents","DeviceFileCertificateInfo","DeviceFileEvents","DeviceImageLoadEvents","DeviceInfo","DeviceLogonEvents","DeviceNetworkEvents","DeviceNetworkInfo","DeviceProcessEvents","DeviceRegistryEvents","DeviceTvmSecureConfigurationAssessment","DeviceTvmSoftwareInventory","DeviceTvmSoftwareVulnerabilities","DnsEvents","DnsInventory","Dynamics365Activity","DynamicSummary","EmailAttachmentInfo","EmailEvents","EmailPostDeliveryEvents","EmailUrlInfo","Event","GCPAuditLogs","HealthStateChangeEvent","Heartbeat","HuntingBookmark","IdentityDirectoryEvents","IdentityInfo","IdentityLogonEvents","IdentityQueryEvents","InsightsMetrics","KubeEvents","KubeHealth","KubeMonAgentEvents","KubeNodeInventory","KubePodInventory","KubeServices","LAQueryLogs","LinuxAuditLog","McasShadowItReporting","MicrosoftPurviewInformationProtection","NetworkSessions","OfficeActivity","Operation","Perf","PowerBIActivity","ProjectActivity","ProtectionStatus","SecureScoreControls","SecureScores","SecurityAlert","SecurityBaseline","SecurityBaselineSummary","SecurityDetection","SecurityEvent","SecurityEvent_598098_SRCH","SecurityIncident","SecurityNestedRecommendation","SecurityRecommendation","SecurityRegulatoryCompliance","SentinelAudit","SentinelHealth","SigninLogs","SqlAtpStatus","SqlVulnerabilityAssessmentResult","SqlVulnerabilityAssessmentScanStatus","Syslog","SysmonEvent","ThreatIntelligenceIndicator","Update","UpdateSummary","UrlClickEvents","Usage","UserAccessAnalytics","UserPeerAnalytics","VMBoundPort","VMComputer","VMConnection","VMProcess","W3CIISLog","Watchlist","WindowsEvent","WindowsFirewall"
$RgName = Read-Host -Prompt "Please enter the resource group name for the Log Analytics workspace"
$WorkName = Read-Host -Prompt "Please enter the WorkspaceName"

foreach ($name in $tables){
Invoke Update-AzOperationalInsightsTable -ResourceGroupName $RgName -WorkspaceName $WorkName -TableName $name -RetentionInDays 90 -TotalRetentionInDays 730
}