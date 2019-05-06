$location = "eastus"
$group = "PacktPublishing"
New-AzureRmResourceGroup -Name $group -Location $location

# Create a New Storage Account within the defined region and resource group
$account = New-AzureRmStorageAccount -ResourceGroupName $group -Name packttestingstorage -Location $location -SkuName Standard_LRS

# Create a new Blog Storage Container within the newly created Storage Account
$key = (Get-AzureRmStorageAccountKey -ResourceGroupName $group -Name $account.Name).Value[0]
$ctx = New-AzureStorageContext -StorageAccountName $account.Name -StorageAccountKey $key
New-AzureStorageContainer -Name testing -Context $ctx

# Create a new Shared Access Policy for the newly created Container within the Storage Account
# Creates a policy with full access to the container based on the Storage Account Context
New-AzureStorageContainerStoredAccessPolicy -Context $ctx -Container testing -Policy "FullAccessPolicy" `
        -Permission "rwdl"