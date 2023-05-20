###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on performing a simple find & replace to swap every occurrence of one string for another,
# across every .md file.
#
# Note: The $find string is case-insensitive.
# Note: Regex is supported in the $find string. Be sure to escape special characters by using the
#       backtick/grave accent (`).
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/Find-and-Replace.ps1



##########################
##  Required Variables  ##
##########################
$gitroot = ""   # Local cloned repository (e.g., "C:\Users\<username>\git\<repo>")
$find = ""      # String to find and replace. Supports regex (see note above)
$replace = ""   # New content to replace the old content



####################
##  Begin Script  ##
####################
$scriptstart = Get-Date

# Get pages
$pages = Get-ChildItem -Path $gitroot -Recurse | where { $_.Extension -eq ".md" }

# Parse Each Page
$pagecnt = 0
$totaledits = 0
$editedpages = 0
$pages | ForEach-Object {
    # Output current page to host
    Write-Host -ForegroundColor Gray ("$($_.FullName.Replace($gitroot,''))")

    # Get page content
    $pagecontent = Get-Content -Encoding UTF8 -LiteralPath $_.FullName

    # Counting/Checking for matches
    $matches = ([regex]::Matches($pagecontent, [regex]::Escape($find), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    if ($matches -gt 0) {

        # Find and replace
        $newcontent = $pagecontent -ireplace [regex]::Escape($find), $replace

        # Save the new content
        $newcontent | Set-Content -Encoding UTF8 -Path $_.FullName

        # Console output plus running tally
        Write-Host -ForegroundColor Cyan "Updated $matches occurrence(s)"
        $totaledits += $matches
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
Write-Host -ForegroundColor Yellow "Occurrences updated: $totaledits"
