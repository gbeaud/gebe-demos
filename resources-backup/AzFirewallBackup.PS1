<#

****************************************************************************************************************************
This Azure Automation runbook automates Azure Firewall backups. It takes snap shots at different instances or schedule and 
saves it to a Blob storage container. It also deletes old backups from blob storage.
 ***************************************************************************************************************************

.DESCRIPTION
	You should use this Runbook if you want to manage Azure Firewall backups in Blob storage or just want to export the current configuration. It
    works as a power runbook. 
	
#>

# param(
#     [parameter(Mandatory=$true)]
# 	[String] $ResourceGroupName,
#     [parameter(Mandatory=$true)]
# 	[String] $AzureFirewallName,
#     [parameter(Mandatory=$true)]
# 	[String] $AzureFirewallPolicy,
#     [parameter(Mandatory=$true)]
#     [String]$StorageAccountName,
#     [parameter(Mandatory=$true)]
#     [String]$StorageKey,
# 	[parameter(Mandatory=$true)]
#     [string]$BlobContainerName,
# 	[parameter(Mandatory=$true)]
#     [Int32]$RetentionDays
# )


$ResourceGroupName = "rg-hub-connectivity-prod-westeu"
$AzureFirewallName = "fw-prod-westeu"
$AzureFirewallPolicy = "fp-firewall-policy-hub-prod-westeu-01"
$storageAccountName = "saresourcesbackup"
$StorageKey = "XXX"
$BlobContainerName = "firewall-backup"
$RetentionDays = 30


$ErrorActionPreference = 'stop'

# function Login() {
# 	$connectionName = "AzureRunAsConnection"
# 	try
# 	{
# 		$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

# 		Write-Verbose "Logging in to Azure..." -Verbose

# 		Add-AzAccount `
# 			-ServicePrincipal `
# 			-TenantId $servicePrincipalConnection.TenantId `
# 			-ApplicationId $servicePrincipalConnection.ApplicationId `
# 			-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null
# 	}
# 	catch {
# 		if (!$servicePrincipalConnection)
# 		{
# 			$ErrorMessage = "Connection $connectionName not established."
# 			throw $ErrorMessage
# 		} else{
# 			Write-Error -Message $_.Exception
# 			throw $_.Exception
# 		}
# 	}
# }

function Create-newContainer([string]$blobContainerName, $storageContext) {
	Write-Verbose "Creating '$blobContainerName' blob container space for storage..." -Verbose
	if (Get-AzureStorageContainer -ErrorAction "Stop" -Context $storageContext | Where-Object { $_.Name -eq $blobContainerName }) {
		Write-Verbose "Container '$blobContainerName' already exists" -Verbose
	} else {
		New-AzureStorageContainer -ErrorAction "Stop" -Name $blobContainerName -Permission Off -Context $storageContext
		Write-Verbose "Container '$blobContainerName' created" -Verbose
	}
}

function Export-To-Storageaccount([string]$resourceGroupName, [string]$AzureFirewallName, [string]$storageKey, [string]$blobContainerName,$storageContext) {
	Write-Verbose "Starting Azure Firewall current configuration export in json..." -Verbose
    try
    {
    $BackupFilename = $AzureFirewallName + (Get-Date).ToString("yyyyMMddHHmm") + ".json"
    $BackupFilePath = ($env:TEMP + "\" + $BackupFilename)
    $AzureFirewallId = (Get-AzFirewall -Name $AzureFirewallName -ResourceGroupName $ResourceGroupName).id
    $FirewallPolicyID = (Get-AzFirewallPolicy -Name $AzureFirewallPolicy -ResourceGroupName $resourceGroupName).id
    Export-AzResourceGroup -ResourceGroupName $resourceGroupName -SkipAllParameterization -Resource @($AzureFirewallId, $FirewallPolicyID) -Path $BackupFilePath
    #Export value and store with name created
    Write-Output "Submitting request to dump Azure Firewall configuration"
    $blobname = $BackupFilename
    $output = Set-AzureStorageBlobContent -File $BackupFilePath -Blob $blobname -Container $blobContainerName -Context $storageContext -Force -ErrorAction stop
    }
	#send out message if backup fails
    catch {
		   $ErrorMessage = "BackUp not created. Please check the input values."
           throw $ErrorMessage
        }
    
}

function Remove-Older-Backups([int]$retentionDays, [string]$blobContainerName, $storageContext) {
	Write-Output "Removing backups older than '$retentionDays' days from blob: '$blobContainerName'"
	$isOldDate = [DateTime]::UtcNow.AddDays(-$retentionDays)
	$blobs = Get-AzureStorageBlob -Container $blobContainerName -Context $storageContext
	foreach ($blob in ($blobs | Where-Object { $_.LastModified.UtcDateTime -lt $isOldDate -and $_.BlobType -eq "BlockBlob" })) {
		Write-Verbose ("Removing blob: " + $blob.Name) -Verbose
		Remove-AzureStorageBlob -Blob $blob.Name -Container $blobContainerName -Context $storageContext
	}
}

Write-Verbose "Starting firewall backup..." -Verbose

$StorageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey

#login to Azure
# Login
# Import-Module Az.Network
# Import-Module Az.Resources

Create-newContainer `
	-blobContainerName $blobContainerName `
	-storageContext $storageContext
	
Export-To-Storageaccount `
	-resourceGroupName $ResourceGroupName `
	-AzureFirewallName $AzureFirewallName `
	-storageKey $StorageKey `
	-blobContainerName $BlobContainerName `
	-storageContext $storageContext
	
Remove-Older-Backups `
	-retentionDays $RetentionDays `
	-storageContext $StorageContext `
	-blobContainerName $BlobContainerName
	
Write-Verbose "Azure Firewall current configuration back up completed." -Verbose