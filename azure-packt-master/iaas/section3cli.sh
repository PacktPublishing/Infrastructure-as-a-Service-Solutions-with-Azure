#!/bin/bash
group = "PacktPublishing"
location = "eastus"

# Create the new VNet with three Subnets
az network vnet create --resource-group $group --location $location --name vnet-pack --address-prefixes "10.0.0.0/24" \
        --subnet-name BaseSubnet --subnet-prefix "10.0.0.0/27"
az network vnet subnet create -resource-group $group --vnet-name vnet-packt --name WebSubnet --address-prefix "10.0.0.32/27"
az network vnet subnet create -resource-group $group --vnet-name vnet-packt --name DBSubnet --address-prefix "10.0.0.64/27"

# Create Public IPs for External Load Balancer and Bastion Host
az network public-ip create --resource-group $group --location $location --name WebLBIP --allocation-method Static \
        --version IPv4 
az network public-ip create --resource-group $group --location $location --name BastionIP --allocation-method Static \
        --version IPv4 

# Only need to create one of the Load Balancers: Internal. The external gets created by the VM Scale Set
dblb = "PacktDBLB"
az network lb create --resource-group $group --name $dblb --location $location 
az network lb frontend-ip create --resource-group $group --name DBFrontEnd --lb-name $dblb \
        --subnet-vnet-name vnet-pack --subnet-name DBSubnet --private-ip-addess "10.0.0.72"
az network lb address-pool create --resource-group $group --lb-name $dblb --name DBBackEnd
az network lb probe create --resource-group $group --lb-name $dblb --name DBHealthProbe --protocol tcp \
        --interval 30 --count 3
az network lb inbound-nat-rule create --resource-group $group --lb-name $dblb --name DBRule1 --frontend-ip-name DBFrontEnd \
        --protocol Tcp --front-port 4306 --backend-port 3306 --idle-timeout 15
az network lb inbound-nat-rule create --resource-group $group --lb-name $dblb --name DBRule2 --frontend-ip-name DBFrontEnd \
        --protocol Tcp --front-port 4307 --backend-port 3306 --idle-timeout 15
az network lb rule create --resource-group $group --lb-name $dblb --name DBRule --protocol Tcp --frontend-port 3306
        --backend-port 3306 --frontend-ip-name DBFrontEnd --backend-pool-name DBBackEnd --probe-name DBHealthProbe