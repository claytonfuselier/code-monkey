###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on idenfitying .archive files and relocating them to the specified location ($graveyard),
# in a subfolder with the current date. This script assumes that pages no longer needed (but not
# deleted), and renamed with the extension ".archive" to prevent them from rendering in the ADO wiki.
#
# You are STRONGLY encouraged to run the orphaned files script to find and clean up any no longer
# needed images, templates, etc. first.
#
# Note: The script will ignore/exclude any files currently in the $graveyard destination.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/archived-pages.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""            # Local cloned repository (e.g., "<drive>:\path\to\repo")
$graveyard = "$gitRoot\.graveyard"          # Where to move archived pages



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Get archived pages
$archivedPages = Get-ChildItem -Path $gitRoot -Filter "*.archive" -Recurse -File | where { $_.DirectoryName -notlike "$graveyard*" }

# Define graveyard
$graveyard = $graveyard + "\archived-" + (Get-Date -Format "yyyyMMdd")

# Parse archived pages
$pageCnt = 0
$movedPages = 0
$errCnt = 0
$archivedPages | ForEach-Object {
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Define destination (and replace missing .md)
    $curRelPath = $_.DirectoryName.Replace($gitRoot, "")
    if ($_.FullName.Split(".")[-2] -contains "md"){
        $dest = $graveyard + $curRelPath
    } else {
        $curRelPath = $curRelPath.Replace(".archive","") + ".md.archive"
        $dest = $graveyard + $curRelPath
        Write-Host -ForegroundColor Cyan "Restored missing `".md`""
    }

    # Create path if non-existent
    if (-not (Test-Path -LiteralPath $dest -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path $dest -ErrorAction SilentlyContinue | Out-Null
    }

    # Move to graveyard
    Move-Item -LiteralPath $_.FullName -Destination $dest
    if ($?) {
        Write-Host -ForegroundColor Cyan "Moved to graveyard"
        $movedPages++
    } else {
        $errCnt++
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($archivedPages.Count – $pageCnt) * $avg)
    $time = New-TimeSpan –Seconds ($msLeft / 1000)
    $percent = [MATH]::Round(($pageCnt / $archivedPages.Count) * 100, 2)
    Write-Progress -Activity "Moving Archived Pages to Graveyard ($percent %)" -Status "$pageCnt of $($archivedPages.Count) total pages - $time" -PercentComplete $percent
}
Write-Host "`n"
Write-Host -ForegroundColor Yellow "Archived Pages Found: $($archivedPages.Count)"
Write-Host -ForegroundColor Yellow "Pages Moved: $movedPages"
Write-Host -ForegroundColor Yellow "Errors: $errCnt"
