###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repositiory).
#
# Focus is on finding "non-page" files (not .md), that are not referenced by any page.
#
# Optional; You can have the identified orphaned files moved to $graveyard.
# - Recommend running script at least once WITHOUT relocating files and reviewing the exported CSV for accuracy.
# - After reviewing/confirming the export, change $relocate to "1" and rerun the script to relocate the files.
#
# Note: Script assumes all templates and attachments are in respective folders.
# Note: Script assumes all attachments are referenced using markdown and not HTML.
# Note: Wrapped/Nested images as links are supported, as well as nested templates (nested to any level/depth).
# Note: Any file in $templatespath or $attachmentspath not referenced by a markdown (.md) file, is considered orphaned.
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/orphaned-files.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""        # Local cloned repository (e.g., "<drive>:\path\to\repo")
$resPaths = "", ""   # (optional) Paths containing known resources (e.g., "path1", "path2", etc.)
$csvExport = ""      # Where to export the CSV (e.g., "<drive>:\path\to\file.csv")
$moveFiles = 0       # 0=No, 1=Yes; Move files to $graveyard
$graveyard = ""      # Where to move archived pages



####################
##  Begin Script  ##
####################

# Get templates/attachments
if ($resources -ne "") {
    Write-Host -ForegroundColor Cyan "Gathering user provided resources..."
    $res = Get-ChildItem -Path $resPaths -Recurse -File
}

# Get all non-pages
Write-Host -ForegroundColor Cyan "Gathering non-pages..."
$nonPages = Get-ChildItem -Path $gitRoot -Recurse -File | where {$_.Extension -ne ".md"`
                                                         -and $_.Extension -ne ".archive"`
                                                         -and $_.BaseName -ne ""}

# Merge $resources and $nonPages
Write-Host -ForegroundColor Cyan "Merging resources and non-pages into single array..."
$files = $nonPages
$filenames = ($files | select FullName).FullName
$res | ForEach-Object {
    if ($filenames -notcontains $_.FullName) {
        $files += $_
    }
}

# Add fields to $files
$scriptStart = Get-Date
Write-Host -ForegroundColor Cyan "Adding additional fields to array..."
$files | ForEach-Object {
    $AdoPath = $_.FullName.Replace($gitRoot,"").Replace("\","/")
    if ($AdoPath[0] -eq "/") {
        $AdoPath = $AdoPath.Substring(1)
    }

    $_ | Add-Member -MemberType NoteProperty -Name "UseCount" -Value 0
    $_ | Add-Member -MemberType NoteProperty -Name "AdoPath" -Value $AdoPath
}

# Get pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File

# Parse pages
$scriptStart = Get-Date
$pageCnt = 0
$pages | ForEach-Object {
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Get page content
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Parse $files in $pageContent
    $files | ForEach-Object {
        # Check if page contains current file
        if ($pageContent -like "*$($_.AdoPath)*") {
            $_.UseCount++
        }
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds/$pageCnt
    $msleft = (($pages.Count–$pageCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msleft/1000)
    $percent = [MATH]::Round(($pageCnt/$pages.Count)*100,2)
    Write-Progress -Activity "Checking for orphaned files: $percent %" -Status "Scanning page $pageCnt of $($pages.Count) for $($files.Count) files - $time" -PercentComplete $percent
}

# Process orphaned files
$scriptStart = Get-Date
$orphanCnt = 0
$orphans = $files | where { $_.UseCount -gt 0 }

$orphans | ForEach-Object {
    # Move orphans
    if ($moveFiles) {
        # Define destination
        $graveyard = $graveyard + "\archived-" + (Get-Date -Format "yyyyMMdd")
        $curRelPath = $_.DirectoryName.Replace($gitRoot, "")
        $dest = $graveyard + $curRelPath

        # Create path if non-existent
        if (-not (Test-Path -LiteralPath $dest -ErrorAction SilentlyContinue)) {
            New-Item -ItemType Directory -Path $dest -ErrorAction SilentlyContinue
        }

        # Move to graveyard
        Move-Item -LiteralPath $_.FullName -Destination $dest
    }

    # Export to CSV
    if ($orphans) {
        foreach ($orphan in $orphans) {
            $item = [pscustomobject]@{
                "DirectoryName" = $_.DirectoryName
                "Name" = $_.Name
                "Extension" = $_.Extension
                "MovedTo" = $dest
            }
            $item | Export-Csv -Path $csvExport -NoTypeInformation -Append
        }
    }

    # Progress bar
    $orphanCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds/$orphanCnt
    $msLeft = (($orphans.Count–$orphanCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msLeft/1000)
    $percent = [MATH]::Round(($orphanCnt/$orphans.Count)*100,2)
    Write-Progress -Activity "Moving Orphan Files to Graveyard ($percent %)" -Status "$orphanCnt of $($orphans.Count) total files - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Exported CSV to `"$csvExport`""
Write-Host -ForegroundColor Yellow "Identified Orphans: $($orphans.Count)"
