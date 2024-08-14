###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on adding ".archive" to all markdown files whose path/name match the specified regex
# pattern. This effectively removes the page from any wiki renderings, but leaves the file in place
# for future reference or un-archival.
#
# Note: The path/name matching is done "relatively". This means the path of $gitroot is ignored for
# matching and only the folder structure beneath $gitroot is evaluated.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/archive-matching-pages.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""            # Local cloned repository (e.g., "<drive>:\path\to\repo")
$regexPattern = ""       # Be sure to use proper character escaping (e.g., "\\path\\to\\match\\on\\")



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Get matching pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File | where {($_.FullName.Replace($gitRoot,"")) -match $regexPattern}

# Parse all pages
$pageCnt = 0
$renamedPages = 0
$failedRenames = 0
$pages | ForEach-Object {
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Add .archive
    Rename-Item -LiteralPath $_.FullName -NewName "$($_.FullName).archive"
    if (-not $?) {
        Write-Host -ForegroundColor Red "Failed to rename page!"
        $failedRenames++
    } else {
        $renamedPages++
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count – $pageCnt) * $avg)
    $time = New-TimeSpan –Seconds ($msLeft / 1000)
    $percent = [MATH]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Renaming pages ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}
Write-Host -ForegroundColor Yellow "Matching Pages: $($pages.Count)"
Write-Host -ForegroundColor Yellow "Pages Renamed: $renamedPages"
if ($failedRenames -gt 0){
    Write-Host -ForegroundColor Red "Failed to Renamed: $failedRenames"
}
