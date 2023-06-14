###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on performing a find and replace operation using a CSV file containing pairs of old and
# new strings. The script will replace every occurrence of an "old" string with its corresponding
# "new" string across all .md files.
#
# Note: The CSV should consist of two columns with the old string in column "OldString" and the new string
#       in column "NewString".
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/Find-and-Replace-Multi-Items.ps1
# Help: https://github.com/claytonfuselier/KM-Scripts/wiki



##########################
##  Required Variables  ##
##########################
$gitroot = ""   # Local cloned repository (e.g., "C:\Users\<username>\git\<repo>")
$csvpath = ""   # Path to CSV file



####################
##  Begin Script  ##
####################
$scriptstart = Get-Date

# Read CSV file into $csvitems
Write-Host -ForegroundColor Gray "Reading CSV file..."
$csvitems = Import-Csv -Path $csvpath | Select-Object -Property @{Name='OldString';Expression={$_.OldString.Trim()}}, @{Name='NewString';Expression={$_.NewString.Trim()}}

# Get pages
$pages = Get-ChildItem -Path $gitroot -Recurse -Filter "*.md" -File

# Parse each page
$pagecnt = 0
$editedpages = 0
$totaledits = 0

$pages | ForEach-Object {
    # Console output of current page
    Write-Host -ForegroundColor Gray ("$($_.FullName.Replace($gitroot,''))")

    # Get page content
    $pagecontent = Get-Content -Encoding UTF8 -LiteralPath $_.FullName

    # Loop through $csvitems checking for matches in $pagecontent
    $edited = 0
    $totalmatches = 0

    $csvitems | ForEach-Object {
        # Counting/Checking for matches
        $matches = ([regex]::Matches($pagecontent, [regex]::Escape($_.OldString), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count

        if ($matches -gt 0) {
            # Find and replace
            $pagecontent = $pagecontent -ireplace [regex]::Escape($_.OldString), $_.NewString
            $edited = 1
            $totalmatches += $matches
        }
    }

    if ($edited) {
        # Save the new content
        $pagecontent | Set-Content -Encoding UTF8 -LiteralPath $_.FullName

        # Console output plus running tally
        Write-Host -ForegroundColor Cyan "Updated $totalmatches Match(es)"
        $totaledits += $totalmatches
        $editedpages++
    }

    # Progress bar
    $pagecnt++
    $avg = ((Get-Date) - $scriptstart).TotalMilliseconds / $pagecnt
    $msleft = (($pages.Count - $pagecnt) * $avg)
    $time = New-TimeSpan -Seconds ($msleft / 1000)
    $percent = [Math]::Round(($pagecnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Scanning pages: $percent %" -Status "$pagecnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Pages updated: $editedpages"
Write-Host -ForegroundColor Yellow "Matches updated: $totaledits"
