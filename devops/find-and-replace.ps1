###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on performing a simple find & replace to swap every occurrence of one string for another,
# across every .md file.
#
# Note: The $find string is case-insensitive.
# Note: Regex is supported in the $find string. Be sure to set $findUseRegex to 1. If using the
#        double-quotes ("), escape it by using the backtick/grave accent (`).
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/find-and-replace.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""       # Local cloned repository (e.g., "<drive>:\path\to\repo")
$find = ""          # String to find and replace. Supports regex (see note above)
$findUseRegex = 0   # 0 or 1. If the $find string is regex, set this to 1. Otherwise leave it as 0.
$replace = ""       # New content to replace the old content



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Get pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File

# Parse each page
$pageCnt = 0
$totalEdits = 0
$editedPages = 0
$pages | ForEach-Object {
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Get page content
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Counting/Checking for matches
    if ($findUseRegex) {
        $matches = ([regex]::Matches($pageContent, $find, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    } else {
        $matches = ([regex]::Matches($pageContent, [regex]::Escape($find), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    }
    if ($matches -gt 0) {

        # Find and replace
        if ($findUseRegex) {
            $newContent = $pageContent -ireplace $find, $replace
        } else {
            $newContent = $pageContent -ireplace [regex]::Escape($find), $replace
        }

        # Save the new content
        Set-Content -LiteralPath $_.FullName -Value $newContent -Encoding UTF8

        # Console output plus running tally
        Write-Host -ForegroundColor Cyan "Updated $matches occurrence(s)"
        $totalEdits += $matches
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
Write-Host -ForegroundColor Yellow "Occurrences updated: $totalEdits"
