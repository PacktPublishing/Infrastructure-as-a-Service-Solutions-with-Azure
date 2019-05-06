$groupName = "PacktPublishing"
$location = "southcentralus"
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $groupName -Name vnet-packt
$bastionip = Get-AzureRmPublicIPAddress -ResourceGroupName $groupName -Name BastionIP
$bastionnsg = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $groupName -Name BastionNICNSG

# Create user object
$cred = Get-Credential -Message 'Enter a username and password for the virtual machine.'

# Create the Bastion Host Standalone Virtual Machine
# Create a virtual network card and associate with public IP address and NSG
$nic = New-AzureRmNetworkInterface -Name BastionNic -ResourceGroupName $groupName -Location $location `
    -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $bastionip.Id -NetworkSecurityGroupId $bastionnsg.Id

# Create a virtual machine configuration
$vmName = "vm-bastion-sc"
$vmConfig = New-AzureRmVMConfig -VMName $vmName -VMSize Standard_D1_V2 | `
            Set-AzureRmVMOperatingSystem -Linux -ComputerName $vmName -Credential $cred | `
            Set-AzureRmVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus "14.04.5-LTS" -Version latest | `
            Add-AzureRmVMNetworkInterface -Id $nic.Id

# Create a virtual machine
New-AzureRmVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig


# Create the DB Servers and add them to a newly created Availability Set and the Internal LB Backend Pool
$dblb = Get-AzureRmLoadBalancerBackendPool -ResourceGroupName $groupName -Name DBLB
$dblbbepool = Get-AzureRmLoadBalancerBackendPoolConfig -Name "DBBackEndPool"  -LoadBalancer $dblb
$dbnsg = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $groupName -Name DBNSG

# Create an availability set.
$as = New-AzureRmAvailabilitySet -ResourceGroupName $groupName -Location $location -Name DBAvailabilitySet `
            -Sku Aligned -PlatformFaultDomainCount 3 -PlatformUpdateDomainCount 3

# Create the NIC Cards for the DB Servers and add to the Internal DB LB
$dbnic1 = New-AzureRmNetworkInterface -ResourceGroupName $groupName -Location $location -Name DBNic1
            -LoadBalancerBackendAddressPool $dblbbepool -NetworkSecurityGroup $dbnsg -Subnet $vnet.Subnets[2]
$dbnic2 = New-AzureRmNetworkInterface -ResourceGroupName $groupName -Location $location -Name 'DBNic2' `
            -LoadBalancerBackendAddressPool $dblbbepool -NetworkSecurityGroup $dbnsg -Subnet $vnet.Subnets[2]

# Create the VMs and Add to the Availability Set
$vmConfig = New-AzureRmVMConfig -VMName "vm-db-sc-1" -VMSize Standard_DS2_V2 -AvailabilitySetId $as.Id | `
            Set-AzureRmVMOperatingSystem -Linux -ComputerName "vm-db-sc-1" -Credential $cred | `
            Set-AzureRmVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus "14.04.5-LTS" -Version latest | `
            Add-AzureRmVMNetworkInterface -Id $dbnic1.Id
$dbVM1 = New-AzureRmVM -ResourceGroupName $groupName -Location $location -VM $vmConfig

# Add a Data Disk to the DB Server
$diskConfig = New-AzureRmDiskConfig -AccountType Premium_LRS -Location southcentralus -CreateOption Empty -DiskSizeGB 128
$dataDisk1 = New-AzureRmDisk -DiskName DiskDBData1 -Disk $diskConfig -ResourceGroupName $groupName
$dbVM1 = Add-AzureRmVMDataDisk -VM $dbVM1 -Name DiskDBData1 -CreateOption Attach -ManagedDiskId $dataDisk1.Id -Lun 1
Update-AzureRmVM -VM $dbVM1 -ResourceGroupName $groupName

# Create the second DB Server and add to the Availability Set
$vmConfig = New-AzureRmVMConfig -VMName "vm-db-sc-2" -VMSize Standard_DS2_V2 -AvailabilitySetId $as.Id | `
            Set-AzureRmVMOperatingSystem -Linux -ComputerName "vm-db-sc-2" -Credential $cred | `
            Set-AzureRmVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus "14.04.5-LTS" -Version latest | `
            Add-AzureRmVMNetworkInterface -Id $dbnic2.Id
New-AzureRmVM -ResourceGroupName $groupName -Location $location -VM $vmConfig

# Add a Data Disk to the DB Server
$dataDisk2 = New-AzureRmDisk -DiskName DiskDBData1 -Disk $diskConfig -ResourceGroupName $groupName
$dbVM2 = Add-AzureRmVMDataDisk -VM $dbVM2 -Name DiskDBData2 -CreateOption Attach -ManagedDiskId $dataDisk2.Id -Lun 1
Update-AzureRmVM -VM $dbVM2 -ResourceGroupName $groupName


#Create the Web Servers as a VM Scale Set
$weblb = Get-AzureLoadBalancer -ResourceGroupName $groupName -Name PacktWebLB
$weblbbepool = Get-AzureRmLoadBalancerBackendPoolConfig -LoadBalancer $weblb -Name WebBackendPool
$weblbnatpool = Get-AzureRmLoadBalancerInbouondNatPoolConfig -LoadBalancer $weblb -Name WebInboundNatPool

# Create a config object
$vmssConfig = New-AzureRmVmssConfig -Location $location -SkuCapacity 2 -SkuName Standard_A2_V2 `
                -UpgradePolicyMode Automatic

# Reference a virtual machine image from the gallery
Set-AzureRmVmssStorageProfile $vmssConfig -ImageReferencePublisher Canonical -ImageReferenceOffer UbuntuServer `
            -ImageReferenceSku "14.04.5-LTS" -ImageReferenceVersion latest

# Set up information for authenticating with the virtual machine
Set-AzureRmVmssOsProfile $vmssConfig -AdminUsername azureuser -AdminPassword P@ssw0rd! -ComputerNamePrefix packtwebvm

## IP address config
$ipConfig = New-AzureRmVmssIpConfig -Name "packt-web-ip" -LoadBalancerBackendAddressPoolsId $weblbbepool.Id ` 
            -SubnetId $vnet.Subnets[1].Id -LoadBalancerInboundNatPoolsId $weblbnatpool.Id

# Attach the virtual network to the IP object
Add-AzureRmVmssNetworkInterfaceConfiguration -VirtualMachineScaleSet $vmssConfig -Name "packt-web-network-config" `
            -Primary $true -IPConfiguration $ipConfig

# Create the scale set with the config object (this step might take a few minutes)
New-AzureRmVmss -ResourceGroupName $groupName -Name "PacktWebScaleSet" -VirtualMachineScaleSet $vmssConfig