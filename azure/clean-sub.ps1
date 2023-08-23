###############
##  Summary  ##
###############
# Remove all Azure resources from a subscription by deleting every resource group. This is done
# asynchronously by creating background PowerShell jobs, which prevents delays while waiting for
# one group to finish deleting before deleting the next.
#
# This script is NOT perfect. I try expand and improve it as I come across blockers/failures while
# using it.
#
# Note: If a resource group is locked or if it contains at least one locked resource, the WHOLE resource
#       group will be skipped.
# Note: If there are cross-dependent resources in different resource groups, there may be dependency
#       related failures for some jobs. Subsequent script executions *should* remove any resource groups
#       that failed previously, assuming the dependencies were removed in the previous execution.
# Note: You can optionally check for and remove certain classic (ASM) resources by setting $skipClassic
#       to $false. This will also require you to have the classic (ASM) module "Azure" installed.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/azure/clean-sub.ps1



##########################
##  Required variables  ##
##########################
$subID = ""               # ID for the subscription to be purged.
$skipClassic = $true      # Whether to skip checking for classic resources; ($true=skip, $false=check)
$showErrors = $false      # Some errors are expected, so they are hidden by default.



####################
##  Begin Script  ##
####################

# Show/Hide errors (Default: Hide)
$Error.Clear()
if (-not $showErrors) {
    $ErrorActionPreference = "SilentlyContinue"
}


# Functions
function SafetyPrompt {
    [string]$prompt = Read-Host -Prompt "Do you want to continue? [Y] Yes or [N] No (default N)"
    if (($prompt -ine "Y") -and ($prompt -ine "YES") -and ($prompt -ine "N") -and ($prompt -ine "NO") -and ($prompt -ine "")) {
       Write-Host -ForegroundColor Red "You have made an invalid selection."
       # Prompt again
       SafetyPrompt 
    }
    
    # Stopping Script
    if (($prompt -ieq "N") -or ($prompt -ieq "NO") -or ($prompt -ieq "")) {
        Write-Host -ForegroundColor Cyan "Prompt response negative. Script execution will now stop. `n"
        exit
    }

    # Continue Script
    if (($prompt -ieq "Y") -or ($prompt -ieq "YES")) {
        Write-Host -ForegroundColor Cyan "Continuing script..."
        return 1
    }
}


function CheckJobs {
    $jobsRunning = 0
    $jobsComplete = 0
    $jobsFailed = 0
    $jobsOther = 0

    $global:jobList | ForEach-Object {
        $job = Get-Job -Id $_
        switch ($job.State) {
            "Running"   {$jobsRunning++}
            "Completed" {$jobsComplete++}
            "Failed"    {$jobsFailed++}
            default     {$jobsOther++}
        }
    }
    if ($jobsRunning -gt 0) {
        Write-Host "$jobsRunning of $($jobList.Count) still running..."
        Start-Sleep 10
        CheckJobs
    } else {
        Write-Host -ForegroundColor Green "All removal jobs have now finished!"
        Write-Host -ForegroundColor Yellow "`t$jobsComplete groups were removed `n`t$jobsFailed groups failed `n`t$global:jobSkip groups were skipped."
        if ($jobsOther -gt 0) {
            Write-Host -ForegroundColor Yellow "`n`t$jobsOther jobs have other statuses."
        }
        Write-Host -ForegroundColor Yellow "You can check the status of individual jobs with Get-Job."
    }
}


# Warning prompt
Write-Host -ForegroundColor Red -BackgroundColor Black "WARNING - This script will attempt to DELETE ALL RESOURCES in subscription '$subID'! This cannot be undone!"
Write-Host -ForegroundColor Yellow `
    "NOTICE:
    Delete jobs may fail if you have cross-dependent resources spread across different resource groups.
    If jobs fail, you can try re-running this script after all jobs have completed. Each run *should* remove a layer of dependency."
$continueScript = SafetyPrompt
if (-not $continueScript) {
    Write-Host -ForegroundColor Cyan "Unexpected response in prompt. Script execution will now stop."
    exit
}


# Check for Az module
Write-Host -ForegroundColor Cyan "Checking for the 'Az' module..."
$az = Get-InstalledModule -Name Az -ErrorAction SilentlyContinue
if ($az) {
    Write-Host -ForegroundColor DarkGray "Version $($az.Version) is installed."
    $latest = (Find-Module -Name Az).Version
    if ($latest -gt $az.Version){
        Write-Host -ForegroundColor DarkGray "Update available ($latest)."
    }
} else {
    Write-Host -ForegroundColor Red "You do not have the Az PowerShell module installed."
    Write-Host -ForegroundColor Yellow "Try installing the module with 'Install-Module -Name Az', then re-run this script."
    exit
}


# Check for the Azure (classic) module
if (-not $skipClassic) {
    Write-Host -ForegroundColor Cyan "Checking for the 'Azure' (classic) module..."
    $asmAzure = (Get-InstalledModule -Name Azure -ErrorAction SilentlyContinue).Version
    if ($asmAzure) {
        Write-Host -ForegroundColor DarkGray "Version $asmAzure is installed."
    } else {
        Write-Host -ForegroundColor Red "You elected to check classic resources but do not have the Azure (classic) PowerShell module installed."
        Write-Host -ForegroundColor Yellow "Try installing the module with 'Install-Module -Name Azure', then re-run this script."
        exit
    }
}


# Login to Azure
Write-Host -ForegroundColor Cyan "Checking if connected to Azure..."
$user = (Get-AzContext).Account.Id
if ($user) {
    Write-Host -ForegroundColor DarkGray "Logged in with the user '$user'"
} else {
    Write-Host -ForegroundColor Cyan "Prompting for authentication..."
    $login = Connect-AzAccount
    if (-not $login) {
        Write-Host -ForegroundColor Red "Authentication to Azure failed or was not completed."
        exit
    }
}


# Login to Azure (classic)
if (-not $skipClassic) {
    Write-Host -ForegroundColor Cyan "Checking if connected to Azure (classic)..."
    $classicUser = (Get-AzureAccount).Id
    if ($classicUser) {
        Write-Host -ForegroundColor DarkGray "Logged in with the user '$classicUser'"
    } else {
        Write-Host -ForegroundColor DarkGray "Not authenticated to Azure (Classic)."
        Write-Host -ForegroundColor Cyan "Prompting for authentication..."
        $classicLogin = Add-AzureAccount
        if (-not $classicLogin) {
            Write-Host -ForegroundColor Red "Authentication to Azure (Classic) failed or was not completed."
            Write-Host -ForegroundColor Red "If you want to skip classic resources, set the '`$skipClassic' variable to '`$true'."
            exit
        }
    }
}


# Select the subscription
Write-Host -ForegroundColor Cyan "Checking subscription..."
$sub = Select-AzSubscription -Subscription $subID
if (-not $sub) {
    Write-Host -ForegroundColor Red "The subscription '$subID' is invalid or could not be found for the user '$user'."
    Write-Host -ForegroundColor DarkGray "If you need to switch accounts, log out with 'Logout-AzAccount' and then re-run this script."
    exit
} else {
    Write-Host -ForegroundColor DarkGray "Located subscription '$subID'."
}


# Select the subscription (classic)
if (-not $skipClassic) {
    Select-AzureSubscription -SubscriptionId $subID
}


# Get resource groups
Write-Host -ForegroundColor Cyan "Getting resource groups..."
$rgList = Get-AzResourceGroup
if ($rgList.Count -lt 1) {
    Write-Host -ForegroundColor DarkGray "You do not have any resource groups to remove."
    exit
}
Write-Host -ForegroundColor DarkGray "Found $($rgList.Count) resource group(s)."


# Get locked resources
Write-Host -ForegroundColor Cyan "Checking for resource locks..."
$locks = Get-AzResourceLock
$lockedRGs = @()
$locks | ForEach-Object {
    $lockedRGs += $_.ResourceGroupName
}
$lockedRGs = $lockedRGs | Select-Object -Unique
Write-Host -ForegroundColor DarkGray "Found $($lockedRGs.Count) resource group(s) that are locked or contain locked resources."


# Recovery vaults
$rsVaults = Get-AzRecoveryServicesVault
if ($rsVaults.Count -gt 0) {
    Write-Host -ForegroundColor Cyan "$($rsVaults.Count) Recovery Service Vaults were identified."
    Write-Host -ForegroundColor Yellow "NOTICE: Removal of Recovery Service Vaults is a lengthy process. Please be patient..."
    # Begin removals
    $rsVaults | ForEach-Object {
        $vault = $_

        # Skip if the RG is locked
        if ($lockedRGs -notcontains $vault.ResourceGroupName) {
            Write-Host -ForegroundColor Cyan "Beginning removal of the vault '$($vault.Name)'..."

            # Set context
            Set-AzRecoveryServicesAsrVaultContext -Vault $vault > $null

            # Disable Soft Delete
            Write-Host -ForegroundColor DarkGray "Disabling soft delete..."
            Set-AzRecoveryServicesVaultProperty -Vault $vault.ID -SoftDeleteFeatureState Disable > $null

            # Undelete items in soft delete state
            $softDeletedItems = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $vault.ID | Where-Object { $_.DeleteState -eq "ToBeDeleted" }
            $softDeletedItems | ForEach-Object { Undo-AzRecoveryServicesBackupItemDeletion -Item $_ -VaultId $vault.ID -Force > $null }

            # Disable security features (Enhanced Security) to remove MARS/MAB/DPM servers
            Write-Host -ForegroundColor DarkGray "Disabling Enhance Security for the vault..."
            Set-AzRecoveryServicesVaultProperty -VaultId $vault.ID -DisableHybridBackupSecurityFeature $true > $null

            ### Stop backup and delete backup items
            # Azure VM
            Write-Host -ForegroundColor DarkGray "Disabling and deleting Azure VM backup items..."
            $backupItemsVM = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $vault.ID
            $backupItemsVM | ForEach-Object { Disable-AzRecoveryServicesBackupProtection -Item $_ -VaultId $vault.ID -RemoveRecoveryPoints -Force > $null }

            # SQL Server in Azure VM
            Write-Host -ForegroundColor DarkGray "Disabling and deleting SQL Server backup items..."
            $backupItemsSQL = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $vault.ID
            $backupItemsSQL | ForEach-Object { Disable-AzRecoveryServicesBackupProtection -Item $_ -VaultId $vault.ID -RemoveRecoveryPoints -Force > $null }
            
            # Disable auto-protection for SQL
            Write-Host -ForegroundColor DarkGray "Disabling auto-protection and deleting SQL protectable items..."
            $protectableItemsSQL = Get-AzRecoveryServicesBackupProtectableItem -WorkloadType MSSQL -VaultId $vault.ID | Where-Object { $_.IsAutoProtected -eq $true }
            $protectableItemsSQL | ForEach-Object { Disable-AzRecoveryServicesBackupAutoProtection -BackupManagementType AzureWorkload -WorkloadType MSSQL -InputItem $_ -VaultId $vault.ID > $null }

            # Unregister SQL Server in Azure VM
            Write-Host -ForegroundColor DarkGray "Deleting SQL Servers in Azure VM containers..."
            $backupContainersSQL = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $vault.ID | Where-Object { $_.ExtendedInfo.WorkloadType -eq "SQL" }
            $backupContainersSQL | ForEach-Object { Unregister-AzRecoveryServicesBackupContainer -Container $_ -Force -VaultId $vault.ID > $null }

            # SAP HANA in Azure VM
            Write-Host -ForegroundColor DarkGray "Disabling and deleting SAP HANA backup items..."
            $backupItemsSAP = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType SAPHanaDatabase -VaultId $vault.ID
            $backupItemsSAP | ForEach-Object { Disable-AzRecoveryServicesBackupProtection -Item $_ -VaultId $vault.ID -RemoveRecoveryPoints -Force > $null }

            # Unregister SAP HANA in Azure VM
            Write-Host -ForegroundColor DarkGray "Deleting SAP HANA in Azure VM containers..."
            $backupContainersSAP = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $vault.ID | Where-Object { $_.ExtendedInfo.WorkloadType -eq "SAPHana" }
            $backupContainersSAP | ForEach-Object { Unregister-AzRecoveryServicesBackupContainer -Container $_ -Force -VaultId $vault.ID > $null }

            # Azure File Shares
            Write-Host -ForegroundColor DarkGray "Disabling and deleting Azure File Share backups..."
            $backupItemsAFS = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureStorage -WorkloadType AzureFiles -VaultId $vault.ID
            $backupItemsAFS | ForEach-Object { Disable-AzRecoveryServicesBackupProtection -Item $_ -VaultId $vault.ID -RemoveRecoveryPoints -Force > $null }

            # Unregister storage accounts
            Write-Host -ForegroundColor DarkGray "Unregistering Storage Accounts..."
            $StorageAccounts = Get-AzRecoveryServicesBackupContainer -ContainerType AzureStorage -VaultId $vault.ID
            $StorageAccounts | ForEach-Object { Unregister-AzRecoveryServicesBackupContainer -Container $_ -Force -VaultId $vault.ID > $null }

            # Unregister MARS servers
            Write-Host -ForegroundColor DarkGray "Deleting MARS Servers..."
            $backupServersMARS = Get-AzRecoveryServicesBackupContainer -ContainerType "Windows" -BackupManagementType MAB -VaultId $vault.ID
            $backupServersMARS | ForEach-Object { Unregister-AzRecoveryServicesBackupContainer -Container $_ -Force -VaultId $vault.ID > $null }

            # Unregister MABS servers
            Write-Host -ForegroundColor DarkGray "Deleting MAB Servers..."
            $backupServersMABS = Get-AzRecoveryServicesBackupManagementServer -VaultId $vault.ID | Where-Object { $_.BackupManagementType -eq "AzureBackupServer" }
            $backupServersMABS | ForEach-Object { Unregister-AzRecoveryServicesBackupManagementServer -AzureRmBackupManagementServer $_ -VaultId $vault.ID > $null }

            # Unregister DPM servers
            Write-Host -ForegroundColor DarkGray "Deleting DPM Servers..."
            $backupServersDPM = Get-AzRecoveryServicesBackupManagementServer -VaultId $vault.ID | Where-Object { $_.BackupManagementType -eq "SCDPM" }
            $backupServersDPM | ForEach-Object { Unregister-AzRecoveryServicesBackupManagementServer -AzureRmBackupManagementServer $_ -VaultId $vault.ID > $null }

            # Remove private endpoints
            Write-Host -ForegroundColor DarkGray "Removing private endpoints..."
            $pvtendpoints = Get-AzPrivateEndpointConnection -PrivateLinkResourceId $vault.ID
            $pvtendpoints | ForEach-Object {
                $peNameSplit = $_.Name.Split(".")
                $peName = $peNameSplit[0]
                # Remove private endpoint connections
                Remove-AzPrivateEndpointConnection -ResourceId $_.Id -Force > $null
                # Remove private endpoints
                Remove-AzPrivateEndpoint -Name $peName -ResourceGroupName $vault.ResourceGroupName -Force > $null
            }

            # Deletion of ASR Items
            $fabricObjects = Get-AzRecoveryServicesAsrFabric
            
            # First DisableDR all VMs.
            $fabricObjects | ForEach-Object {
                $fabricObject = $_
                $containerObjects = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabricObject
                $containerObjects | ForEach-Object {
                    # DisableDR all protected items
                    $protectedItems = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $_
                    $protectedItems | ForEach-Object {
                        Write-Host -ForegroundColor DarkGray "Triggering DisableDR(Purge) for item:" $_.Name
                        Remove-AzRecoveryServicesAsrReplicationProtectedItem -InputObject $_ -Force > $null
                    }

                    # Remove all Container Mappings
                    $containerMappings = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $_
                    $containerMappings | ForEach-Object {
                        Write-Host -ForegroundColor DarkGray "Triggering Remove Container Mapping: " $_.Name
                        Remove-AzRecoveryServicesAsrProtectionContainerMapping -InputObject $_ -Force > $null
                    }
                }
                $netObjects = Get-AzRecoveryServicesAsrNetwork -Fabric $fabricObject
                $netObjects | ForEach-Object {
                    # Get the PrimaryNetwork
                    $primaryNetwork = Get-AzRecoveryServicesAsrNetwork -Fabric $fabricObject -FriendlyName $_
                    $netMappings = Get-AzRecoveryServicesAsrNetworkMapping -Network $primaryNetwork
                    $netMappings | ForEach-Object {
                        # Get the Network Mappings
                        $netMapping = Get-AzRecoveryServicesAsrNetworkMapping -Name $_.Name -Network $primaryNetwork
                        Remove-AzRecoveryServicesAsrNetworkMapping -InputObject $netMapping > $null
                    }
                }
                # Remove Fabric
                Write-Host -ForegroundColor DarkGray "Triggering Remove Fabric:" $fabricObject.FriendlyName
                Remove-AzRecoveryServicesAsrFabric -InputObject $fabricObject -Force
                Write-Host -ForegroundColor DarkGray "Removed Fabric."
            }

            $accessToken = Get-AzAccessToken
            $token = $accessToken.Token
            $authHeader = @{
                'Content-Type'='application/json'
                'Authorization'='Bearer ' + $token
            }
            $restUri = 'https://management.azure.com/subscriptions/'+$subID+'/resourcegroups/'+$vault.ResourceGroupName+'/providers/Microsoft.RecoveryServices/vaults/'+$vault.Name+'?api-version=2021-06-01&operation=DeleteVaultUsingPS'
            $response = Invoke-RestMethod -Uri $restUri -Headers $authHeader -Method DELETE
            $vaultDeleted = Get-AzRecoveryServicesVault -Name $vault.Name -ResourceGroupName $vault.ResourceGroupName -ErrorAction 'SilentlyContinue'
            if ($vaultDeleted -eq $null) {
                Write-Host -ForegroundColor Cyan "Completed removal of vault '$($vault.Name)'..."
            }
        }
    }
}


# Classic Resources
if (-not $skipClassic) {
    # Storage accounts (classic) pending migration
    Write-Host -ForegroundColor DarkGray "Aborting storage (classic) migrations..."
    $storagePending = Get-AzureStorageAccount | Where-Object { $_.MigrationState -ne $null }
    $storagePending | ForEach-Object { Move-AzureStorageAccount -StorageAccountName $_.StorageAccountName -Abort > $null }
        
    # VM Images (classic)
    Write-Host -ForegroundColor DarkGray "Deleting VM Images (classic)..."
    $classicImages = Get-AzureVMImage | Where-Object { $_.PublisherName -eq $null }
    $classicImages | ForEach-Object{ Remove-AzureVMImage -ImageName $_.ImageName -DeleteVHD > $null }

    # Disks (classic)
    Write-Host -ForegroundColor DarkGray "Deleting disks (classic)..."
    $classicDisks = Get-AzureDisk
    $classicDisks | ForEach-Object { Remove-AzureDisk -DiskName $_.DiskName -DeleteVHD > $null }
}


# Remove Resource Groups
Write-Host -ForegroundColor Cyan "Beginning to remove resource groups..."
Get-Job | Remove-Job > $null
$jobCnt = 0
$jobSkip = 0
$jobList = @()
$rgList | ForEach-Object {
    if (($_.ProvisioningState -eq "Succeeded") -and ($lockedrgs -notcontains $_.ResourceGroupName)) {
        $delRG = Remove-AzResourceGroup -Name $_.ResourceGroupName -Force -AsJob
        if ($delRG) {
            Write-Host "Started job (ID $($delRG.Id)) to remove resource group '$($_.ResourceGroupName)'."
            $jobList += $delRG.ID
            $jobCnt++
        } else {
            Write-Host -ForegroundColor Red "Failed to start job to remove resource group '$($_.ResourceGroupName)'"
        }
    } else {
        Write-Host -ForegroundColor DarkGray "Skipping resource group '$($_.ResourceGroupName)'."
        $jobSkip++
    }
}
Write-Host -ForegroundColor Green "Started $jobCnt job(s) to remove resource groups. (Skipped $jobSkip resource group(s))"
Write-Host -ForegroundColor DarkGray "The script will continue to monitor the progress of each job. `nIf you prefer, you can cancel the monitoring with Ctrl+C and use Get-Job to monitor the progress for yourself."


# Looping CheckJobs function
CheckJobs
