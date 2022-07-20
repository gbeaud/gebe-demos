<#
    .DESCRIPTION
        Backs up both the Azure Firewall configurations and its policy as an ARM JSON template in a storage account. To be run in an automation account.

    .NOTES
        AUTHOR: Guillaume Beaud (CSA)
        LASTEDIT: July 4th, 2022
#>

############### Variables definitions

# Subscription ID where the resources to be operated are located
$firewallSubscriptionId = "XXX"
$storageAccountSubscriptionId = "YYY"
$firewallResourceGroupName = "rg-hub-connectivity-prod-westeu"
$storageAccountResourceGroupName = "rg-management-storage-prod-westeu-01"
$azureFirewallName = "fw-prod-westeu"
$azureFirewallPolicy = "fp-firewall-policy-hub-prod-westeu-01"
$storageAccountName = "saresourcesbackup"
$blobContainerName = "firewall-backup"

############### Context setup

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process | Out-Null

# Connect using a Managed Service Identity
try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Set context
Set-AzContext -SubscriptionId $firewallSubscriptionId

############### Tasks to be performed

# Define a unique name and path to store the ARM template JSON file
$backupFilename = $azureFirewallName + (Get-Date).ToString("yyyyMMddHHmm") + ".json"
$backupFilePath = ($env:TEMP + "\" + $backupFilename)

# Retrieve objects IDs
$azureFirewallId = (Get-AzFirewall -Name $azureFirewallName -ResourceGroupName $firewallResourceGroupName).id
$firewallPolicyID = (Get-AzFirewallPolicy -Name $azureFirewallPolicy -ResourceGroupName $firewallResourceGroupName).id

# Exports the firewall + policy as an ARM template
Export-AzResourceGroup -ResourceGroupName $firewallResourceGroupName -SkipAllParameterization -Resource @($azureFirewallId, $firewallPolicyID) -Path $backupFilePath

# Export value and store with name created
Set-AzContext -SubscriptionId $storageAccountSubscriptionId
Write-Output "Submitting request to dump Azure Firewall configuration"
$blobname = $backupFilename
$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName)| Where-Object {$_.KeyName -eq "key1"}
$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey.value
# Write file to storage account
Set-AzureStorageBlobContent -File $backupFilePath -Blob $blobname -Container $blobContainerName -Context $storageContext -Force -ErrorAction stop