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
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/find-and-replace-multi-items.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""   # Local cloned repository (e.g., "<drive>:\path\to\repo")
$csvPath = ""   # Path to CSV file



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Read CSV file into $csvItems
Write-Host -ForegroundColor Gray "Reading CSV file..."
$csvItems = Import-Csv -Path $csvPath | Select-Object -Property @{Name='OldString';Expression={$_.OldString.Trim()}}, @{Name='NewString';Expression={$_.NewString.Trim()}}

# Get pages
$pages = Get-ChildItem -Path $gitRoot -Recurse -Filter "*.md" -File

# Parse each page
$pageCnt = 0
$editedPages = 0
$totalEdits = 0

$pages | ForEach-Object {
    # Console output of current page
    Write-Host -ForegroundColor Gray ("$($_.FullName.Replace($gitRoot,''))")

    # Get page content
    $pageContent = Get-Content -Encoding UTF8 -LiteralPath $_.FullName

    # Loop through $csvItems checking for matches in $pageContent
    $edited = 0
    $totalMatches = 0

    $csvItems | ForEach-Object {
        # Counting/Checking for matches
        $matches = ([regex]::Matches($pageContent, [regex]::Escape($_.OldString), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count

        if ($matches -gt 0) {
            # Find and replace
            $pageContent = $pageContent -ireplace [regex]::Escape($_.OldString), $_.NewString
            $edited = 1
            $totalMatches += $matches
        }
    }

    if ($edited) {
        # Save the new content
        $pageContent | Set-Content -Encoding UTF8 -LiteralPath $_.FullName

        # Console output plus running tally
        Write-Host -ForegroundColor Cyan "Updated $totalMatches Match(es)"
        $totalEdits += $totalMatches
        $editedPages++
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) - $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count - $pageCnt) * $avg)
    $time = New-TimeSpan -Seconds ($msLeft / 1000)
    $percent = [Math]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Scanning pages: $percent %" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Pages updated: $editedPages"
Write-Host -ForegroundColor Yellow "Matches updated: $totalEdits"
