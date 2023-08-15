###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on adding a header/footer or other content to the top or bottom of all .md files.
#
# Note: The script ignores files located under any "hidden" paths that begin with a period (".").
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/add-header-or-footer.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required variables  ##
##########################
$gitRoot = ""       # Local cloned repository (e.g., "<drive>:\path\to\repo")
$addWhere = "top"   # Add the content at the top or bottom of the page? (e.g., "top" or "bottom")
$newContent = ""    # Content to add (line breaks are supported)



####################
##  Begin Script  ##
####################
$scriptStartTime = Get-Date
$pageCnt = 0
$updPageCnt = 0

# Get all pages
$pages = Get-ChildItem -Path $gitRoot -Recurse | where { $_.Extension -eq ".md" -and $_.DirectoryName -notlike "*.*" }

# Parse each page
$pages | ForEach-Object {
    $fullPath = $_.FullName
    $_.FullName.Replace($gitRoot, "") | Write-Host

    # Get page contents and add new content
    switch ($addWhere) {
        "top" { $pageContent = $newContent + "`n" + (Get-Content -LiteralPath $fullPath -Raw); break }
        "bottom" { $pageContent = (Get-Content -LiteralPath $fullPath -Raw) + "`n" + $newContent; break }
        default { Write-Host -ForegroundColor Red -BackgroundColor Black "You must specify a valid value for `"`$addWhere`" before executing this script."; exit }
    }

    # Save modified page content
    Set-Content -LiteralPath $fullPath -Encoding UTF8 -Value $pageContent
    $updPageCnt++

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) - $scriptStartTime).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count - $pageCnt) * $avg)
    $time = New-TimeSpan -Seconds ($msLeft / 1000)
    $percent = [Math]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Adding content... ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host "Pages Updated: $updPageCnt"
