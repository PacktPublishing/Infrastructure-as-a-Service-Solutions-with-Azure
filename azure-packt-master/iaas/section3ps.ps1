$location = "southcentralus"
$group = "PacktPublishing"
New-AzureRmResourceGroup -Name $group -Location $location

# Create Virtual Network and Related Subnets
$vnet = New-AzureRmVirtualNetwork -Name vnet-packt -ResourceGroupName $group -Location $location `
                -AddressPrefix "10.0.0.0/24"

Add-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name BaseSubnet -AddressPrefix "10.0.0.32/27"
Add-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name WebSubnet -AddressPrefix "10.0.0.64/27"
Add-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name DBSubnet -AddressPrefix "10.0.0.96/27"

Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

# Create Public IPs for External Load Balancer and Bastion Host
$weblbip = New-AzureRmPublicIpAddress -Name WebLBIP -ResourceGroupName $group -Location $location `
                -AllocationMethod Static -IpAddressVersion IPv4 -IdleTimeoutInMinutes 4
$bastionip = New-AzureRmPublicIpAddress -Name BastionIP -ResourceGroupName $group -Location $location `
                -AllocationMethod Static -IpAddressVersion IPv4 -IdleTimeoutInMinutes 4

# Only need to create one of the Load Balancers: Internal. The external gets created by the VM Scale Set
$dbfrontendip = New-AzureRmLoadBalancerFrontendIpConfig -Name DBFrontEnd -Subnet $vnet.Subnets[2]
$dbhealthprobe = New-AzureRmLoadBalancerProbeConfig -Name DBHealthProbe -Protocol Tcp -Port 3306 -IntervalInSeconds 30 `
                -ProbeCount 3
$dbbackendpool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name DBBackEnd
$dbnatrule1 = New-AzureRmLoadBalancerInboundNatRuleConfig -Name DBRule1 -FrontendIpConfigurationId $dbfrontendip.Id `
                -FrontendPort 4306 -BackendPort 3306 -Protocol Tcp -IdleTimeoutInMinutes 15
$dbnatrule2 = New-AzureRmLoadBalancerInboundNatRuleConfig -Name DBRule2 -FrontendIpConfigurationId $dbfrontendip.Id `
                -FrontendPort 4307 -BackendPort 3306 -Protocol Tcp -IdleTimeoutInMinutes 15
$dblbrule = New-AzureRmLoadBalancerRuleConfig -Name DBRule -FrontendIpConfigurationId $dbfrontendip.Id -Protocol Tcp `
                -BackendAddressPoolId $dbbackendpool.Id -ProbeId $dbhealthprobe.Id -FrontendPort 443 -BackendPort 443
$dblb = New-AzureRmLoadBalancer -Name PacktDBLB -ResourceGroupName $group.ResourceGroupName -Location $location `
                -FrontendIpConfiguration $dbfrontendip -Probe $dbhealthprobe -BackendAddressPool $dbbackendpool `
                -InboundNatRule $dbnatrule1,$dbnatrule2 -LoadBalancingRule $dblbrule


# Create all of the Rules and corresponding NSG for the Web Subnet
$internetinrule = New-AzureRmNetworkSecurityRuleConfig -Name InWebRule -Protocol Tcp -Priority 100 `
                -SourcePortRange 443 -SourceAddressPrefix "0.0.0.0/0" -Access Allow `
                -DestinationPortRange 443 -DestinationAddressPrefix $weblbip.IpAddress
$internetoutrule = New-AzureRmNetworkSecurityRuleConfig -Name OutWebRule -Protocol Tcp -Priority 100 `
                -SourcePortRange 443 -SourceAddressPrefix $weblbip.IpAddress -Access Allow `
                -DestinationPortRange 443 -DestinationAddressPrefix "0.0.0.0/0"
$dbinrule = New-AzureRmNetworkSecurityRuleConfig -Name InDBRule -Protocol Tcp -Priority 110 `
                -SourcePortRange 3306 -SourceAddressPrefix $vnet.Subnets[2].AddressPrefix -Access Allow `
                -DestinationPortRange 3306 -DestinationAddressPrefix $vnet.Subnets[1].AddressPrefix
$dboutrule = New-AzureRmNetworkSecurityRuleConfig -Name OutDBRule -Protocol Tcp -Priority 110 -Access Allow `
                -SourcePortRange 3306 -SourceAddressPrefix $vnet.Subnets[1].AddressPrefix `
                -DestinationPortRange 3306 -DestinationAddressPrefix $vnet.Subnets[2].AddressPrefix
$websshinrule = New-AzureRmNetworkSecurityRuleConfig -Name InSSHRule -Protocol Tcp -Priority 120 -Access Allow `
                -SourcePortRange * -SourceAddressPrefix $vnet.Subnets[0].AddressPrefix
                -DestinationAddressPrefix $vnet.Subnets[1].AddressPrefix -DestinationPortRange 22
$websshoutrule = New-AzureRmNetworkSecurityRuleConfig -Name OutSSHRule -Protocol Tcp -Priority 120 -Access Allow `
                -SourcePortRange * -SourceAddressPrefix $vnet.Subnets[1].AddressPrefix 
                -DestinationPortRange 22 -DestinationAddressPrefix $vnet.Subnets[0].AddressPrefix
$websubnetnsg = New-AzureRmNetworkSecurityGroup -Name WebSubnetNSG -ResourceGroupName $group.Name -Location southcentralus `
                -SecurityRules $dbinrule,$dboutrule,$internetinrule$internetoutrule,$websshinrule,$websshoutrule
Set-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -NetworkSecurityGroup $websubnetnsg -Name WebSubnet

# Create all of the Rules and corresponding NSG for the DB Subnet
$dbinrule2 = New-AzureRmNetworkSecurityRuleConfig -Name InDBRule -Protocol Tcp -Priority 100 `
            -SourcePortRange 3306 -SourceAddressPrefix $vnet.Subnets[1].AddressPrefix -Access Allow `
            -DestinationPortRange 3306 -DestinationAddressPrefix $vnet.Subnets[2].AddressPrefix
$dboutrule2 = New-AzureRmNetworkSecurityRuleConfig -Name OutDBRule -Protocol Tcp -Priority 100 -Access Allow `
            -SourcePortRange 3306 -SourceAddressPrefix $vnet.Subnets[2].AddressPrefix `
            -DestinationPortRange 3306 -DestinationAddressPrefix $vnet.Subnets[1].AddressPrefix
$dbsshinrule = New-AzureRmNetworkSecurityRuleConfig -Name InSSHRule -Protocol Tcp -Priority 110 -Access Allow `
            -SourcePortRange * -SourceAddressPrefix $vnet.Subnets[0].AddressPrefix
            -DestinationAddressPrefix $vnet.Subnets[2].AddressPrefix -DestinationPortRange 22
$dbsshoutrule = New-AzureRmNetworkSecurityRuleConfig -Name OutSSHRule -Protocol Tcp -Priority 110 -Access Allow `
            -SourcePortRange * -SourceAddressPrefix $vnet.Subnets[2].AddressPrefix 
            -DestinationPortRange 22 -DestinationAddressPrefix $vnet.Subnets[0].AddressPrefix
$dbsubnetnsg = New-AzureRmNetworkSecurityGroup -Name DBSubnetNSG -ResourceGroupName $group.Name -Location southcentralus `
            -SecurityRules $dbinrule2,$dboutrule2,$dbsshinrule,$dbsshoutrule
Set-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -NetworkSecurityGroup $dbsubnetnsg -Name DBSubnet

# Create all of the Rules and corresponding NSG for the Bastion VM - attaching when the VM is created
$sshinrule = New-AzureRmNetworkSecurityRuleConfig -Name InSSHRule -Protocol Tcp -Priority 100 -Access Allow `
            -SourcePortRange * -SourceAddressPrefix VirtualNetwork
            -DestinationAddressPrefix $vnet.Subnets[0].AddressPrefix -DestinationPortRange 22
$sshoutrule = New-AzureRmNetworkSecurityRuleConfig -Name OutSSHRule -Protocol Tcp -Priority 100 -Access Allow `
            -SourcePortRange * -SourceAddressPrefix $vnet.Subnets[0].AddressPrefix 
            -DestinationPortRange 22 -DestinationAddressPrefix VirtualNetwork
New-AzureRmNetworkSecurityGroup -Name BastionNICNSG -ResourceGroupName $group.Name -Location southecentralus `
            -SecurityRules $sshinrule,$sshoutrule