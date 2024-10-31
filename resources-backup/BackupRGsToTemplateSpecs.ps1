<#
    .SYNOPSIS
        Export multiple resource groups as template specs (versioned ARM templates stored and easily deployable in Azure)
    .DESCRIPTION
        - This script is geared towards backup of Azure resources configuration
        - Template specs are stored in the same resource group they extract
        - Removes versions older than the set retention period
        - Can be run on the entire tenant, entire subscriptions or selected resource groups
        - Usual limitations of ARM apply: "WARNING: ExportTemplateCompletedWithErrors" may be triggered because some resources cannot be exported as templates (e.g. Log Analytics workspaces etc...)
    .PARAMETER scopes
        Defines the scope over which the script will run; either 
            1) on the entire tenant
            2) on entire subscriptions
            3) on selected resource groups
        Option 1: entire tenant => $scopes=$null
        Option 2: on entire subscriptions => $scopes = @{'<subId>' = $null}
        Option 3: on selected resource groups (you can also add entire subs) => 
            $scopes = @{
                '<subId1>' = @('rg-01', 'rg-02')
                '<subId2>' = @('rg-03')
                '<subId3>' = $null # entire sub
            }
    .PARAMETER retentionDays
        Retention period in days for template spec versions; all versions older than the retention period will be deleted during next run
    .NOTES
        AUTHOR: Guillaume Beaud (Microsoft Cloud Solution Architect)
        LASTEDIT: November 17th, 2022
#>

# To cover specific subscriptions / resource groups
$scopes = @{
    '<subId1>' = @('rg-01', 'rg-02')
    '<subId2>' = @('rg-03')
    '<subId3>' = $null # entire sub
}

# To cover the entire tenant
# $scopes = $null

$retentionDays = 365

function Export-ResourceGroup(
    [string]$resourceGroupName,
    [int]$retentionDays) {
    <#
    .SYNOPSIS
        Export a single, entire resource group as an ARM template spec and store it in the resource group
    #>

    Write-Host "Processing resource group: $resourceGroupName ... `n"

    # Trim the name since template spec versions only support 90 characters
    $templateVersion = ($resourceGroupName[0..70] -join '') + '_' + (Get-Date).ToString('yyyy-MM-dd-HH-mm')
    $backupFilename = $templateVersion + '.json'
    $backupFilePath = ($env:TEMP + '\' + $backupFilename)

    # Collect all objects in the resource group excluding template specs and their versions
    $objectsExcludingTemplates = Get-AzResource -ResourceGroupName $resourceGroupName |
    Where-Object { $_.ResourceType -ne 'Microsoft.Resources/templateSpecs' `
            -and $_.ResourceType -ne 'Microsoft.Resources/templateSpecs/versions' }

    # Export the resource group as ARM JSON excluding template specs and their versions, only if the list of objects is not null
    if ($null -ne $objectsExcludingTemplates) {

        # Create the ARM template JSON file and save it locally
        Export-AzResourceGroup -Force -ResourceGroupName $resourceGroupName -Resource @($objectsExcludingTemplates.ResourceID) -SkipAllParameterization -Path $backupFilePath

        # Trim name since template spec names only support 90 characters
        $templateSpecName = 'ts-' + ($resourceGroupName[0..80] -join '')

        # Create a template spec from the local ARM JSON file
        New-AzTemplateSpec `
            -Name $templateSpecName `
            -Version $templateVersion `
            -ResourceGroupName $resourceGroupName `
            -Location (Get-AzResourceGroup -Name $resourceGroupName).Location `
            -TemplateFile $backupFilePath `
            -Force
    
        # Calling function to remove old versions of template specs
        Remove-OldTemplates -resourceGroupName $resourceGroupName -templateSpecName $templateSpecName -retentionDays $retentionDays

        Write-Host -ForegroundColor Green "Resource group $resourceGroupName successfully exported! `n"
    }
    else {
        Write-Output "Resource group $resourceGroupName has no resources to export. `n"
    }
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

function Export-Subscriptions {
    <#
    .SYNOPSIS
        Iterate over scoped subscriptions and resource groups to call Export-ResourceGroup
    #>
    param (
        [int]$retentionDays,
        $scopes
    )
    # If $scope is null, all resource groups in the entire tenant are exported
    if ($null -eq $scopes) {
        foreach ($subscription in Get-AzSubscription) {
            Set-AzContext -Subscription $subscription
            Write-Host -ForegroundColor DarkMagenta "`nProcessing subscription:" (Get-AzSubscription -SubscriptionId $subscription).Name
            foreach ($resourceGroup in Get-AzResourceGroup) {
                Export-ResourceGroup `
                    -resourceGroupName $resourceGroup.ResourceGroupName `
                    -retentionDays $retentionDays
            }
        }
    }
    else {
        foreach ($scope in $scopes.GetEnumerator()) {
            Set-AzContext -Subscription $scope.Name
            Write-Host -ForegroundColor DarkMagenta "`nProcessing subscription:" (Get-AzSubscription -SubscriptionId $scope.Name).Name
            if ($null -eq $scope.Value) {
                # If there is no resource group in the scope, the script applies to the entire subscription
                foreach ($resourceGroup in Get-AzResourceGroup) {
                    Export-ResourceGroup `
                        -resourceGroupName $resourceGroup.ResourceGroupName `
                        -retentionDays $retentionDays
                }
            } else {
                # Otherwise, the script exports only the selected resource groups
                foreach ($resourceGroup in $scope.Value) {
                    Export-ResourceGroup `
                        -resourceGroupName $resourceGroup  `
                        -retentionDays $retentionDays
                }
            }
        }
    }
    Write-Host -ForegroundColor Green "Scoped resource groups successfully exported!"
}

# If using an Automation account, connect using a Managed Service Identity. Otherwise remove this block.
try {
    'Logging in to Azure...'
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Run export
Export-Subscriptions -scopes $scopes -retentionDays $retentionDays