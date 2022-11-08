<#
    .DESCRIPTION
        Export all resource groups from all subscriptions as template specs stored in the related resource group
        Removes versions older than the set retention period
        Usual limitations of ARM apply (e.g. it will not export Log Analytics workspaces due to OperationalInsights objects not being exportable, etc...)
    .PARAMETER retentionDays
        Retention period in days for template spec versions
    .NOTES
        AUTHOR: Guillaume Beaud (Microsoft Cloud Solution Architect)
        LASTEDIT: November 8th, 2022
#>

$retentionDays = 365

function Export-ResourceGroup(
    [string]$subscriptionID, 
    [string]$resourceGroupName) {
    <#
    .SYNOPSIS
        Export a single, entire resource group as an ARM template spec and store it in the resource group
    #>

    # Trim the name since template spec versions only support 90 characters
    $templateVersion = ($resourceGroupName[0..70] -join '') + '_' + (Get-Date).ToString('yyyy-MM-dd-HH-mm')
    $backupFilename = $templateVersion + '.json'
    $backupFilePath = ($env:TEMP + '\' + $backupFilename)

    # Switch to the workload's subscription
    Select-AzSubscription -SubscriptionId $subscriptionID

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
    }
    else {
        Write-Output "Resource group $resourceGroupName has no resources to export."
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

function Export-AllSubscriptions() {
    <#
    .SYNOPSIS
        Iterate over all available subscriptions and all resource groups to call Export-ResourceGroup
    #>
    foreach ($subscription in Get-AzSubscription) {
        Select-AzSubscription -SubscriptionId $subscription
        foreach ($resourceGroup in Get-AzResourceGroup) {
            Export-ResourceGroup `
                -resourceGroupName $resourceGroup.ResourceGroupName `
                -SubscriptionId $subscription
        }
    }
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
Export-AllSubscriptions