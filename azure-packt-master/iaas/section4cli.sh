#!/bin/bash
group = "PacktPublishing"
location = "eastus"
vnet = "vnet-packt"
bastionip = "BastionIP"
bastionnsg = "BastionNICNSG"

# Create the Bastion Host Standalone Virtual Machine
# Create a virtual network card and associate with public IP address and NSG
az network nic create --resource-group $group --name BastionNIC --subnet BaseSubnet --location $location \
            --public-ip-address $bastionip --network-security-group $bastionnsg --vnet-name $vnet

# Create a virtual machine configuration
vmName = "vm-bastion-sc"
az compute vm --resource-group $group --name $vmName --admin-username brianadmin --location $location \
            --size Standard_D1_V2 --authentication-type password --admin-password B0bb@F3tt0911 --nics BastionNIC \
            --image UbuntuLTS

# Create the DB Servers and add them to a newly created Availability Set and the Internal LB Backend Pool
dblb = "PacktDBLB"
dblbbepool = "DBBackendPool"
dbnsg = "DBNSG"

az vm availability-set create --resource-group $group --location $location --name DBAvailabilitySet \
            --platform-update-domain-count 2 --platform-fault-domain-count 2 

# Create the two NICs for the DB Servers and add to the Internal LB Backend Pool
az network nic create --resource-group $group --name DBNIC1 --subnet DBSubnet --location $location \
            --vnet-name $vnet --lb-name $dblb --lb-address-pools $dblbbepool
az network nic create --resource-group $group --name DBNIC2 --subnet DBSubnet --location $location \
            --vnet-name $vnet --lb-name $dblb --lb-address-pools $dblbbepool