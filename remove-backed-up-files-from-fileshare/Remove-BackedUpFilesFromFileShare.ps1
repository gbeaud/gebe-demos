<#
    .DESCRIPTION
        Removes files in multiple file shares when the file is older than a set retention period and the file share has been backed up between now and the retention period
        Can be run from an automation account by uncommenting the block at the end
    .PARAMETER subscriptionID
    .PARAMETER resourceGroupName
    .PARAMETER storageAccountName
        Storage account hosting the file shares
    .PARAMETER fileShareNames
        List of strings containing the name of the file shares
        Pattern: 'fs-file-share-dev-01', 'fs-file-share-dev-02', 'fs-file-share-dev-03'
    .PARAMETER vaultName
        Name of the recovery services vault where backups are located
    .PARAMETER retentionDays
        Retention period in days
        All files older than this period located in a file share that has been backed up since this retention period will be deleted
    .NOTES
        AUTHOR: Guillaume Beaud (Microsoft Cloud Solution Architect)
        LASTEDIT: November 11th, 2022
#>

$subscriptionID = 'XXX'
$resourceGroupName = 'rg-file-share-backup-script-dev-westeu-01'
$storageAccountName = 'safilesharebackupscript'
[String[]]$fileShareNames = 'fs-file-share-dev-01', 'fs-file-share-dev-02', 'fs-file-share-dev-03'
$vaultName = 'rsv-backup-vault-file-share-dev-westeu-01'
$retentionDays = 7

function Remove-BackedUpFiles {
    param (
        [string]$fileShareName
    )
    <#
    .SYNOPSIS
        Removes files in the file share older than $retentionDays only if they are backed up in the recovery vault
        Only processes one file share per function call
    #>

    # `n adds a line break in output
    Write-Host "`nProcessing file share $fileShareName ..."

    # Get the recovery services vault
    $vault = Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupName -Name $vaultName
    # Get the container inside the vault
    $container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureStorage -FriendlyName $storageAccountName -VaultId $vault.ID
    # Get the backup item inside the container, which represents the file share
    $backupItem = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureFiles -VaultId $vault.ID -FriendlyName $fileShareName
 
    # Checking if the last backup has completed, if the protection status is healthy and if the date of the last backup is greater than now minus the retention period
    if (($backupItem.LastBackupStatus -eq 'Completed') -and ($backupItem.ProtectionStatus -eq 'Healthy') -and ($backupItem.LastBackupTime -gt (Get-Date).AddDays(- $retentionDays))) {

        Write-Host -ForegroundColor Green 'Backup status of file share:' $backupItem.LastBackupStatus
        Write-Host -ForegroundColor Green 'Protection status of file share:' $backupItem.ProtectionStatus
        Write-Host -ForegroundColor Green 'Time of last backup of file share:' $backupItem.LastBackupTime

        # Proceeding with files cleanup
        Write-Host "Listing files in file share $fileShareName :"
        # Get the storage account context  
        $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName).Context  
        # Flag to inform user if no file is deleted
        [bool] $deletionFlag = $false
        $files = Get-AzStorageFile -Context $ctx -ShareName $fileShareName
        foreach ($file in $files) {
            # `t adds a tab to indent text
            Write-Host -ForegroundColor Magenta `t 'File Name:' $file.Name, ' Last Modified:' $file.FileProperties.LastModified
            if ($file.FileProperties.LastModified.AddDays($retentionDays) -lt (Get-Date)) {
                Write-Host 'File older than' $retentionDays 'days. Proceeding with file deletion.'
                # Remove file
                $file | Remove-AzStorageFile
                $deletionFlag = $true
                Write-Host -ForegroundColor Green 'File' $file.Name 'in file share' $fileShareName 'was succesfully removed.'
            }
        }
        # If the deletion flag is false, inform that no file was deleted
        if (!$deletionFlag) {
            Write-Output "No file older than $retentionDays days. No file has been deleted in $fileShareName."
        }
    }
    else {
        Write-Host -ForegroundColor Yellow "Status or time of the file share's last backup does not meet requirements. No file will be deleted in $fileShareName."
    }
}

function Invoke-AllFileSharesCleanup {
    <#
    .SYNOPSIS
        Iteratively calls the function Remove-BackedUpFiles on each file share
    #>
    foreach ($fileShare in $fileShareNames) {
        Remove-BackedUpFiles -fileShare $fileShare
    }
}

# If using an Automation account, connect using a Managed Service Identity and uncomment the below block. For local testing, comment this block.
# try {
#     'Logging in to Azure...'
#     Connect-AzAccount -Identity
# }
# catch {
#     Write-Error -Message $_.Exception
#     throw $_.Exception
# }

Select-AzSubscription -SubscriptionId $subscriptionID
# Trigger functions
Invoke-AllFileSharesCleanup