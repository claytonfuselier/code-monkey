###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on adding a header/footer or other content to the top or bottom of all .md files.
#
# Note: The script ignores files located under any "hidden" paths that begin with a period (".").
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/Add-Header-or-Footer.ps1
# Help: https://github.com/claytonfuselier/KM-Scripts/wiki



##########################
##  Required variables  ##
##########################
$gitroot = ""       # Local cloned repository (e.g., "<drive>:\path\to\repo")
$addwhere = "top"   # Add the content at the top or bottom of the page? (e.g., "top" or "bottom")
$newcontent = ""    # Content to add (line breaks are supported)



####################
##  Begin Script  ##
####################
$scriptstarttime = Get-Date
$pagecnt = 0
$updpagecnt = 0

# Get all pages
$pages = Get-ChildItem -Path $gitroot -Recurse | where { $_.Extension -eq ".md" -and $_.DirectoryName -notlike "*.*" }

# Parse each page
$pages | ForEach-Object {
    $fullpath = $_.FullName
    $_.FullName.Replace($gitroot, "") | Write-Host

    # Get page contents and add new content
    switch ($addwhere) {
        "top" { $pagecontent = $newcontent + "`n" + (Get-Content -LiteralPath $fullpath -Raw); break }
        "bottom" { $pagecontent = (Get-Content -LiteralPath $fullpath -Raw) + "`n" + $newcontent; break }
        default { Write-Host -ForegroundColor Red -BackgroundColor Black "You must specify a valid value for `"`$addwhere`" before executing this script."; exit }
    }

    # Save modified page content
    Set-Content -LiteralPath $fullpath -Encoding UTF8 -Value $pagecontent
    $updpagecnt++

    # Progress bar
    $pagecnt++
    $avg = ((Get-Date) - $scriptstarttime).TotalMilliseconds / $pagecnt
    $msleft = (($pages.Count - $pagecnt) * $avg)
    $time = New-TimeSpan -Seconds ($msleft / 1000)
    $percent = [Math]::Round(($pagecnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Adding content... ($percent %)" -Status "$pagecnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host "Pages Updated: $updpagecnt"
