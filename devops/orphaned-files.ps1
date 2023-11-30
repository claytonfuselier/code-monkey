###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repositiory).
#
# Focus is on finding resources (files without .md extension), that are not referenced by on pages.
#
# Additionally, you can provide path(s) for $userResPath and every file (including .md) will be
# evaluated to see if it is in-use by other pages or has been orphaned. This is useful if you have
# template .md pages that are embedded in other pages, and stored in a central local (e.g. "./templates").
#
# Optional: Set $moveFiles to 1 ("yes"), to have any identified orphaned files moved to $graveyard.
# - Recommendation is to run the script at least once WITHOUT moving files ($moveFiles = 0) and reviewing
#   the exported CSV for accuracy first.
#
# Note: $userResPaths supports multiple paths using the following syntax:
#       $userResPaths = "drive:\path\to\include", "drive:\another\path\to\include"
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/Orphaned-Files.ps1



##########################
##  Required Variables  ##
##########################
$gitRoot = ""             # Local cloned repository (e.g., "<drive>:\path\to\repo")
$userResPaths = "", ""    # (optional) Paths containing known resources (e.g., "path1", "path2", etc.)
$graveyard = "$gitRoot\.graveyard"   # Location for archived pages (e.g., "$gitRoot\.graveyard")
$moveFiles = 0            # 0=No, 1=Yes; Move files to $graveyard
$csvExport = ".\OrphanedFiles.csv"   # Where to export the CSV (e.g., "<drive>:\path\to\file.csv")



####################
##  Begin Script  ##
####################

# Get pages
Write-Host -ForegroundColor Cyan "Gathering pages..."
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File | where { $_.DirectoryName -ne $graveyard }

# Get all non-page files
Write-Host -ForegroundColor Cyan "Gathering non-page files..."
$files = Get-ChildItem -Path $gitRoot -Recurse -File | where { $_.DirectoryName -ne $graveyard`
                                                         -and $_.Extension -ne ".md"`
                                                         -and $_.Extension -ne ".archive"`
                                                         -and $_.BaseName -ne "" }

# Get user provided resources
if ($userResPaths -ne "") {
    Write-Host -ForegroundColor Cyan "Gathering files in user provided path(s)..."
    $userRes = Get-ChildItem -Path $userResPaths -Recurse -File | where { $_.BaseName -ne "" }

    # Merge $userRes and $files
    Write-Host -ForegroundColor Cyan "Merging user provided files and non-page files into single array..."
    $filenames = ($files | select FullName).FullName
    $userRes | ForEach-Object {
        if ($filenames -notcontains $_.FullName) {
            $files += $_
        }
    }
}

# Add additional properties to $files
Write-Host -ForegroundColor Cyan "Finalizing array..."
$files | ForEach-Object {
    $AdoPath = $_.FullName.Replace($gitRoot,"").Replace("\","/")
    if ($AdoPath[0] -eq "/") {
        $AdoPath = $AdoPath.Substring(1)
    }

    $_ | Add-Member -MemberType NoteProperty -Name "UseCount" -Value 0
    $_ | Add-Member -MemberType NoteProperty -Name "AdoPath" -Value $AdoPath
}

# Define search blocks
Write-Host -ForegroundColor Cyan "Defining search blocks of 100 from array..."
$searchBlocks = @()
$rMin = 0
$rMax = 100
$cur = 0
while ($rMin -le $files.Count) {
    $pattern = "("
    # Create each block of 100
    while ($cur -le $rMax) {
        if ($files[$cur].AdoPath -ne $null) {
            $separator = "|"
            if ($cur -eq $rMax -or $cur -eq ($files.Count -1)) {
                $separator = ""
            }
            $pattern = "$pattern" + [regex]::Escape($files[$cur].AdoPath) + "$separator"
        }
        $cur++
    }
    $pattern = "$pattern" + ")"
    $searchBlocks += $pattern
    $rMin += 100
    $rMax += 100
}

# Parse pages
Write-Host -ForegroundColor Cyan "Scanning each page..."
$startPages = Get-Date
$pageCnt = 0
$pages | ForEach-Object {
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Get page content
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Parse $pageContent for $searchBlocks
    $curBlock = 0
    $searchBlocks | ForEach-Object {
        # Check if current block matches page
        if ($pageContent -match $_) {
            # Check each file in current block
            $curFile = $curBlock * 100
            $blockEnd = $curFile + 99
            while ($curFile -le $blockEnd -and $curFile -lt $files.Count) {
                if ($pageContent -match [regex]::Escape($files[$curFile].AdoPath)) {
                    # Updating matched file UseCount
                    $files[$curFile].UseCount++
                    $matches++
                }
                $curFile++
            }
        }
        $curBlock++
    }
    if ($matches -gt 0) {
        Write-Host -ForegroundColor Cyan "Updated $matches files in array"
    }
    $matches = 0

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $startPages).TotalMilliseconds/$pageCnt
    $msleft = (($pages.Count–$pageCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msleft/1000)
    $percent = [MATH]::Round(($pageCnt/$pages.Count)*100,2)
    Write-Progress -Activity "Checking for orphaned files: $percent %" -Status "Scanning page $pageCnt of $($pages.Count), for $($files.Count) files - $time" -PercentComplete $percent
}

# Process orphaned files
$orphanStart = Get-Date
$orphanCnt = 0
$orphans = $files | where { $_.UseCount -eq 0 }
$orphans | ForEach-Object {
    # Move orphans
    if ($moveFiles) {
        # Define destination
        $curRelPath = $_.DirectoryName.Replace($gitRoot, "")
        $dest = $graveyard + "\archived-" + (Get-Date -Format "yyyyMMdd") + $curRelPath

        # Create path if non-existent
        if (-not (Test-Path -LiteralPath $dest -ErrorAction SilentlyContinue)) {
            New-Item -ItemType Directory -Path $dest -ErrorAction SilentlyContinue
        }

        # Move to graveyard
        Move-Item -LiteralPath $_.FullName -Destination $dest
    }

    # Export to CSV
    $exportRow = [pscustomobject]@{
        "DirectoryName" = $_.DirectoryName
        "Name" = $_.Name
        "Extension" = $_.Extension
        "MovedTo" = $dest
    }
    $exportRow | Export-Csv -Path $csvExport -NoTypeInformation -Append

    # Progress bar
    $orphanCnt++
    $avg = ((Get-Date) – $orphanStart).TotalMilliseconds/$orphanCnt
    $msLeft = (($orphans.Count–$orphanCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msLeft/1000)
    $percent = [MATH]::Round(($orphanCnt/$orphans.Count)*100,2)
    Write-Progress -Activity "Processing orphaned files ($percent %)" -Status "$orphanCnt of $($orphans.Count) total files - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Identified Orphans: $($orphans.Count)"
if ($moveFiles) {
    Write-Host -ForegroundColor Yellow "Moved to: $graveyard"
}
Write-Host -ForegroundColor Yellow "Exported CSV: `"$csvExport`""
