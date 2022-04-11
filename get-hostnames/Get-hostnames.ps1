$report = @()
Get-AzSubscription | % {
Select-AzSubscription $_
    $vms = Get-AzVM
    $publicIps = Get-AzPublicIpAddress
    $nics = Get-AzNetworkInterface | ?{ $_.VirtualMachine -NE $null}
    foreach ($nic in $nics) {
        $info = "" | Select-Object VmName, ResourceGroupName, Region, VirturalNetwork, Subnet, PrivateIpAddress, OsType, PublicIPAddress, SubscriptionName
        $vm = $vms | ? -Property Id -eq $nic.VirtualMachine.id
        foreach($publicIp in $publicIps) {
            if($nic.IpConfigurations.id -eq $publicIp.ipconfiguration.Id) {
                $info.PublicIPAddress = $publicIp.ipaddress
            }
        }
        $info.OsType = $vm.StorageProfile.OsDisk.OsType
        $info.VMName = $vm.Name
        # $info.ResourceGroupName = $vm.ResourceGroupName
        # $info.Region = $vm.Location
        # $info.VirturalNetwork = $nic.IpConfigurations.subnet.Id.Split("/")[-3]
        # $info.Subnet = $nic.IpConfigurations.subnet.Id.Split("/")[-1]
        $info.PrivateIpAddress = $nic.IpConfigurations.PrivateIpAddress
        $info.SubscriptionName=$_.Name
        $report+=$info
    }
}
$report | Select-Object VmName, ResourceGroupName, Region, VirtualNetwork, Subnet,`
    @{label="PrivateIpAddress";expression={$_.PrivateIpAddress}}, PublicIPAddress, OsType, `
    SubscriptionName | Export-Csv -NoTypeInformation "VMs_$(Get-Date -Uformat "%Y%m%d-%H%M%S").csv"