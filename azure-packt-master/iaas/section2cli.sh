#!/bin/bash
group = "PacktPublishing"
location = "eastus"
account = "packttestingstorage"

az group create --name $group --location $location

# Create a New Storage Account within the defined region and resource group
az storage account create --resource-group-name $group --location $location --sku Standard_LRS --name $account
az storage account show --resource-group $group --name $account

# Copy one of the Storage Account Keys into this variable so that it can be used later.
# There are ways to get this value directly from the generated JSON in the above show command. I reccomend the jq library
# https://stedolan.github.io/jq/
key = <storage_account_key>

# Creae a new Storage Container within the storage account created above
az storage container create --account-name $account --acount-key $key --name testing

# Create a SAS Policy for the newly created container
az storage container generate-sas --name testing --account-key $key --account-name $account --permissions "rwdl"