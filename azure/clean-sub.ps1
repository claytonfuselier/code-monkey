###############
##  Summary  ##
###############
# Quickly delete all Azure resouces from a subscription by deleting all resource groups. This is done
# asynchronously by creating background jobs, which prevents delays while waiting for one group to
# finish deleting before deleting the next.
#
# Note: If a resource group is locked, or if it contains at least one locked resource, the WHOLE resource
#       group will be skipped.
# Note: If there are cross-dependent resouces in different resouce groups, there may be dependency
#       related failures for some jobs. Subsequent script executions *should* remove any resource groups
#       that failed previously. Assuming the dependencies were removed in the previous execution.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/azure/clean-sub.ps1



##########################
##  Required variables  ##
##########################
$subid = ""               # ID for the subscription to be purged.
$showerrors = $false      # Some errors are expected, so they are hidden by default.



####################
##  Begin Script  ##
####################

# Show/Hide errors (Default: Hide)
$Error.Clear()
if (-not $showerrors) {
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


function CheckJobs ($jobList) {
    $jobsRunning = 0
    $jobsComplete = 0
    $jobsFailed = 0
    $jobList | ForEach-Object {
        $job = Get-Job -Id $_
        if ($job.State -eq "Running") {
            $jobsRunning++
        }
        if ($job.State -eq "Completed") {
            $jobsComplete++
        }
        if ($job.State -eq "Failed") {
            $jobsFailed++
        }
    }
    if ($jobsRunning -gt 0) {
        Write-Host "$jobsRunning of $($jobList.Count) still running..."
        Start-Sleep 10
        CheckJobs -jobList $jobList
    } else {
        $jobsOther = $jobList.Count - $jobsComplete - $jobsFailed
        Write-Host -ForegroundColor Green "All jobs have now finished!"
        Write-Host -ForegroundColor Yellow "`t$jobsComplete jobs are Complete `n`t$jobsFailed jobs are Failed"
        if ($jobsOther -gt 0) {
            Write-Host -ForegroundColor Yellow "`n`t$jobsOther jobs have other statuses."
        }
        Write-Host -ForegroundColor Yellow "You can check the status of individual jobs with Get-Job."
    }
}


function LatestModVer ($mod, $curVer) {
    $latest = (Find-Module -Name $mod).Version
    if ($latest -gt $curVer){
        Write-Host -ForegroundColor DarkGray "Update available ($latest)."
    } else {
        Write-Host -ForegroundColor DarkGray "Using latest version."
    }
}



# Warning prompt
Write-Host -ForegroundColor Red "WARNING - This script will attempt to DELETE ALL RESOURCES in subscription '$subid'! This cannot be undone!"
Write-Host -ForegroundColor DarkGray `
    "Note:
    Delete jobs may fail if you have cross-dependent resources spread across different resource groups.
    If jobs fail, you can try re-running this script after all jobs have completed. Each run *should* remove a layer of dependency."
$continueScript = SafetyPrompt
if (-not $continueScript) {
    Write-Host -ForegroundColor Cyan "Unexpected return value for variable `$continueScript. Script execution will now stop." -verbose
    exit
}


# Check for Az module
Write-Host -ForegroundColor Cyan "Checking for Az module..."
$az = (Get-InstalledModule -Name Az -ErrorAction SilentlyContinue).Version
if (-not $az) {
    Write-Host -ForegroundColor Red "You do not have the Az PowerShell module installed."
    Write-Host -ForegroundColor DarkGray "Try installing the module with 'Install-Module -Name Az', then re-run this script."
    exit
}
if ($az) {
    Write-Host -ForegroundColor DarkGray "Version $az is installed."
    LatestModVer -mod Az -curVer $az
}


# Remove any old jobs
Write-Host -ForegroundColor Cyan "Removing existing PowerShell jobs..."
Get-Job | Remove-Job



# Login to Azure
Write-Host -ForegroundColor Cyan "Checking if connected to Azure..."
$user = (Get-AzContext).Account.Id
if (-not $user) {
    Write-Host -ForegroundColor DarkGray "Not authenticated."
    Write-Host -ForegroundColor Cyan "Prompting for authentication..."
$login = Connect-AzAccount
    if (-not $login) {
        Write-Host -ForegroundColor Red "Authentication to Azure failed or was not completed."
        exit
    }
} else {
    Write-Host -ForegroundColor DarkGray "Logged in with user '$user'"
}


# Select Subscription
Write-Host -ForegroundColor Cyan "Checking subscription..."
$sub = Select-AzSubscription -Subscription $subid
if (-not $sub) {
    Write-Host -ForegroundColor Red "Subscription '$subid' is invalid, or could not be found for user '$user'."
    Write-Host -ForegroundColor DarkGray "If you need to switch accounts, logout with 'Logout-AzAccount'and then re-run this script."
    exit
} else {
    Write-Host -ForegroundColor DarkGray "Located subscription '$subid'."
}


# Get resource groups
Write-Host -ForegroundColor Cyan "Getting resource groups..."
$rglist = Get-AzResourceGroup
if ($rglist -lt 1) {
    Write-Host -ForegroundColor DarkGray "You do not have any resource groups."
    exit
}
Write-Host -ForegroundColor DarkGray "Found $($rglist.Count) resource group(s)."


# Get locked resources
Write-Host -ForegroundColor Cyan "Checking for resource locks..."
$locks = Get-AzResourceLock
$lockedrgs = @()
$locks | ForEach-Object {
    $lockedrgs += $_.ResourceGroupName
}
$lockedrgs = $lockedrgs | select -Unique
Write-Host -ForegroundColor DarkGray "Found $($lockedrgs.Count) resource group(s) that are locked or contain locked resources."


# Remove Resource Groups
Write-Host -ForegroundColor Cyan "Beginning to remove resource groups..."
$jobCnt = 0
$jobSkip = 0
$jobList = @()
$rgList | ForEach-Object {
    if (($_.ProvisioningState -eq "Succeeded") -and ($lockedrgs -notcontains $_.ResourceGroupName)) {
        $delRg = Remove-AzResourceGroup -Name $_.ResourceGroupName -Force -AsJob
        if ($delRg) {
            Write-Host "Started job (ID $($delRg.Id)) to remove group '$($_.ResourceGroupName)'."
            $jobList += $delRg.ID
            $jobCnt++
        } else {
            Write-Host "Failed to start job to remove group '$($_.ResourceGroupName)'."
        }
    } else {
        $jobSkip++
    }
}
Write-Host -ForegroundColor Green "Started $jobCnt job(s) to remove resource groups. (Skipped $jobSkip resource group(s))"
Write-Host -ForegroundColor DarkGray "The script will continue to monitor the progress of each job. `nIf you prefer, you can cancel the monitoring with Ctrl+C and use Get-Job to monitor the progress for yourself."


# Looping CheckJobs function
CheckJobs -jobList $jobList


# Remaining resource groups
$rglist = Get-AzResourceGroup
if($rglist -gt 0){
    Write-Host -ForegroundColor DarkGray "You have $($rglist.Count) resource group(s) remaining."
}
