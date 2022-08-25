<#
    .DESCRIPTION
        Export all resource groups from all subscriptions as template specs stored in the related resource group.
        Usual limitations of ARM apply (e.g. it will not export Log Analytics workspaces due to OperationalInsights objects not being exportable, etc...)
    .NOTES
        AUTHOR: Guillaume Beaud (Microsoft Cloud Solution Architect)
        LASTEDIT: July 20th, 2022
#>

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
    }
    else {
        Write-Output "Resource group $resourceGroupName has no resources to export."
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

# Connect Automation account using a Managed Service Identity
try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Run export
Export-AllSubscriptions