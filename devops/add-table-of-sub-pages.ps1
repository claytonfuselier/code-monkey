###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on adding a Table of Sub Pages (i.e., "[[_TOSP_]]") to all wiki folder pages. If the page
# does not exist, then one is created.
#
# Note: A "wiki folder page" is a page at the same level of a directory with the same basename as
#       the directory.
#       Ex: "/example/path/FolderName" and "/example/path/FolderName.md"
# Note: The script only adds the TOSP item to the bottom of existing pages.
# Note: Hidden directories (and thier sub-directories) are ignored.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/add-table-of-sub-pages.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""     # Local cloned repository (e.g., "<drive>:\path\to\repo")



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Get directories
$dirs = Get-ChildItem -Path $gitRoot -Recurse -Directory | where { $_.FullName -notlike "*.*" }

# Parse directories
$dirCnt = 0
$updateCnt = 0
$dirs | ForEach-Object {
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")
    # Define folder page
    $cur = $_.Parent.FullName + "\" + $_.Name + ".md"
    # Check if folder page exists
    if (Test-Path -LiteralPath $cur){
        # Get page content
        $pageContent = Get-Content -LiteralPath $cur -Encoding UTF8
        # Check if TOSP already exists
        if (-not ($pageContent -match "\[\[_TOSP_\]\]")) {
            # Add TOSP to existing page
            $newContent = $pageContent + "`n`n<br>`n`n[[_TOSP_]]`n"
            Set-Content -LiteralPath $cur -Value $newContent
            Write-Host -ForegroundColor Cyan "Added TOSP"
            $updateCnt++
        }
    } else {
        # Create new page
        $newPageContent = "<!-- DO NOT DELETE THIS PAGE. It is used as a landing page for the $($_.Name.Replace('-',' ')) folder. -->`n# $($_.Name.Replace('-',' '))`n`n<br>`n`n[[_TOSP_]]"
        Set-Content -LiteralPath $cur -Value $newPageContent
        Write-Host -ForegroundColor Cyan "Created new page and added TOSP"
        $updateCnt++
    }

    # Progress bar
    $dirCnt++
    $avg = ((Get-Date) - $scriptStart).TotalMilliseconds / $dirCnt
    $msLeft = (($dirs.Count - $dirCnt) * $avg)
    $time = New-TimeSpan -Seconds ($msLeft / 1000)
    $percent = [Math]::Round(($dirCnt / $dirs.Count) * 100, 2)
    Write-Progress -Activity "Scanning: $percent %" -Status "$dirCnt of $($dir.Count) total directories - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Updated/Created Pages: $updateCnt"
