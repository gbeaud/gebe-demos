$ResourceGroupName = "rg-hub-connectivity-prod-westeu"
$AzureFirewallName = "fw-prod-westeu"
$AzureFirewallPolicy = "fp-firewall-policy-hub-prod-westeu-01"
$storageAccountName = "saresourcesbackup"
$StorageKey = "XXX"
$BlobContainerName = "firewall-backup"

$BackupFilename = $AzureFirewallName + (Get-Date).ToString("yyyyMMddHHmm") + ".json"
$BackupFilePath = ($env:TEMP + "\" + $BackupFilename)
$AzureFirewallId = (Get-AzFirewall -Name $AzureFirewallName -ResourceGroupName $ResourceGroupName).id
$FirewallPolicyID = (Get-AzFirewallPolicy -Name $AzureFirewallPolicy -ResourceGroupName $resourceGroupName).id

#Exports the firewall + policy as an ARM template
Export-AzResourceGroup -ResourceGroupName $resourceGroupName -SkipAllParameterization -Resource @($AzureFirewallId, $FirewallPolicyID) -Path $BackupFilePath #.\$BackupFilename

#Export value and store with name created
Write-Output "Submitting request to dump Azure Firewall configuration"
$blobname = $BackupFilename
$StorageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey
#Write file to storage account
$output = Set-AzureStorageBlobContent -File $BackupFilePath -Blob $blobname -Container $blobContainerName -Context $storageContext -Force -ErrorAction stop

# Deploy the created template
New-AzResourceGroupDeployment -name $azurefirewallname -ResourceGroupName $resourcegroupname -TemplateFile $BackupFilePath