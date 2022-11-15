<#
    .SYNOPSIS
        Backup Azure Firewalls and all their dependent resources as templates in Azure
    .DESCRIPTION
        Export all firewall-related resources (including firewalls, firewall policies, IP groups and public IPs) as a single template spec object stored in the firewall's resource group, which provides a backup with a three-click re-deployment option
        The script looks for firewall-related resource types and can cover all resource groups in the entire tenant, or a defined set of resource groups 
        The script removes template specs versions older than the set retention period
        This script is intended to be run in an automation account as a scheduled job (e.g. running every day), but can also be run locally
    .PARAMETER scopes
        Defines the scope over which the script will run; either 1) on the entire tenant, or 2) on selected resource groups
        Option 1: entire tenant => $scopes = $null
        Option 2: on selected resource groups =>
            Pattern is: @("<subscriptionID>","<resourceGroupName1>","<resourceGroupName2>, ...")
            Example:
            $scopes = @{
                'bh6zu7l9-49e2-47f4-8059-87377ebce92b' = @('rg-sandbox-test-westeu-01', 'rg-network-test-westeu-01')
                'er23fg57-6ce0-4fe8-81a6-97d7ef0d9d38' = @('rg-hub-connectivity-prod-westeu-01')
            }
    .PARAMETER retentionDays
        Retention period in days for template spec versions; all versions older than the retention period will be deleted at next run
    .NOTES
        AUTHOR: Guillaume Beaud (Microsoft Cloud Solution Architect)
        LASTEDIT: November 15th, 2022
#>

# To cover specific subscriptions / resource groups
$scopes = @{
    'bh6zu7l9-49e2-47f4-8059-87377ebce92b' = @('rg-sandbox-test-westeu-01', 'rg-network-test-westeu-01')
    'er23fg57-6ce0-4fe8-81a6-97d7ef0d9d38' = @('rg-hub-connectivity-prod-westeu-01')
}
# To cover the entire tenant
# $scopes = $null
$retentionDays = 365

function Backup-Firewall {
    param (
        [string]$resourceGroupName,
        [int]$retentionDays
    )
    <#
    .SYNOPSIS
        Creates a backup of all firewall-related resources in a given resource group
        Saves resources as an ARM template spec and store it in the resource group
    #>

    Write-Host "`nProcessing resource group $resourceGroupName ..."

    # Collect all objects in the resource group related to firewalls: firewall, firewall policies and ip groups
    $firewallObjects = @(Get-AzResource -ResourceGroupName $resourceGroupName | Where-Object { $_.ResourceType -eq 'Microsoft.Network/firewallPolicies' -or $_.ResourceType -eq 'Microsoft.Network/ipGroups' -or $_.ResourceType -eq 'Microsoft.Network/azureFirewalls' })

    # If there is no firewall-related object in the resource group, the function ends and the script continues to the next resource group
    if ($firewallObjects.Count -eq 0) {
        Write-Host -ForegroundColor Yellow "No firewall-related resources were found in resource group $resourceGroupName - proceeding with next resource group"
        return
    }
    else {
        Write-Host -ForegroundColor Green "Firewall-related resources were found in resource group $resourceGroupName - proceeding with resources backup"
    }

    $firewall = Get-AzFirewall -ResourceGroupName $resourceGroupName
    if ($null -ne $firewall) {
       
        # Get public IP names from the firewall's IP configurations
        $publicIpNames = $firewall.IpConfigurations.Name
        
        # Adding all public IP objects to the list of firewall-related objects
        $firewallObjects += @($publicIpNames | ForEach-Object { Get-AzResource -Name $_ | Where-Object { $_.ResourceType -eq 'Microsoft.Network/publicIPAddresses' } })
    }

    # Trim the name since template spec versions only support 90 characters
    $templateVersion = 'firewall-' + ($resourceGroupName[0..60] -join '') + '_' + (Get-Date).ToString('yyyy-MM-dd-HH-mm')
    $backupFilename = $templateVersion + '.json'
    $backupFilePath = ($env:TEMP + '\' + $backupFilename)

    # Create the ARM template JSON file and save it locally
    Export-AzResourceGroup -Force -ResourceGroupName $resourceGroupName -Resource @($firewallObjects.ResourceID) -SkipAllParameterization -Path $backupFilePath

    # Trim name since template spec names only support 90 characters
    $templateSpecName = 'ts-firewall-' + ($resourceGroupName[0..70] -join '')

    # Create a template spec from the local ARM JSON file
    New-AzTemplateSpec `
        -Name $templateSpecName `
        -Version $templateVersion `
        -ResourceGroupName $resourceGroupName `
        -Location (Get-AzResourceGroup -Name $resourceGroupName).Location `
        -TemplateFile $backupFilePath `
        -Force

    Write-Host -ForegroundColor Green "Firewall-related resources for resource group $resourceGroupName were successfully backed up as template spec!"

    # Calling function to remove old versions of template specs
    Remove-OldTemplates -resourceGroupName $resourceGroupName -templateSpecName $templateSpecName -retentionDays $retentionDays
}

function Remove-OldTemplates {
    <#
    .SYNOPSIS
        Deletes all versions of the template spec older than the given retention period in days
    #>
    param (
        [string]$resourceGroupName,
        [string]$templateSpecName,
        [int]$retentionDays
    )
 
    $templateSpec = Get-AzTemplateSpec -ResourceGroupName $resourceGroupName -Name $templateSpecName

    foreach ($version in $templateSpec.Versions) {
        if ($version.CreationTime.AddDays($retentionDays) -lt (Get-Date)) {
            Write-Host 'Deleting template spec version:' $version.Name
            Remove-AzTemplateSpec -Force -ResourceGroupName $resourceGroupName -Name $templateSpec.Name -Version $version.Name
        } 
    }
}

function Backup-Subscriptions {
    <#
    .SYNOPSIS
        Iterate over all scoped subscriptions and all resource groups to call Backup-Firewall
    #>
    param (
        [int]$retentionDays,
        $scopes
    )

    if ($null -eq $scopes) {
        foreach ($subscription in Get-AzSubscription) {
            Set-AzContext -Subscription $subscription
            Write-Host -ForegroundColor DarkMagenta "`nProcessing subscription:" (Get-AzSubscription -SubscriptionId $subscription).Name
            foreach ($resourceGroup in Get-AzResourceGroup) {
                Backup-Firewall `
                    -resourceGroupName $resourceGroup.ResourceGroupName `
                    -retentionDays $retentionDays
            }
        }
    }
    else {
        foreach ($scope in $scopes.GetEnumerator()) {
            Set-AzContext -Subscription $scope.Name
            Write-Host -ForegroundColor DarkMagenta "`nProcessing subscription:" (Get-AzSubscription -SubscriptionId $scope.Name).Name
            foreach ($resourceGroup in $scope.Value) {
                Backup-Firewall `
                    -resourceGroupName $resourceGroup  `
                    -retentionDays $retentionDays
            }
        }
    }
}

# If using an Automation account, connect using a Managed Service Identity. If running locally, comment this block.
try {
    'Logging in to Azure...'
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Run backup
Backup-Subscriptions -retentionDays $retentionDays -scopes $scopes