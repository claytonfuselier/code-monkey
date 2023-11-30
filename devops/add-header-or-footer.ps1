###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
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
$addWhere = "top"   # Where to add the content? (e.g., "top", "bottom", "topaftertags")
$newContent = ""    # Content to add (line breaks are supported with `n)



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date
$pageCnt = 0
$updPageCnt = 0

# Get all pages
$pages = Get-ChildItem -Path $gitRoot -Include "*.md" -Recurse -File | where { $_.DirectoryName -notlike "*.*" }

# Parse each page
$pages | ForEach-Object {
    $_.FullName.Replace($gitRoot, "") | Write-Host
    # Get page contents
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8
    $modifiedContent = $null

    # Modify page content
    switch ($addWhere) {
        "top" {
            $modifiedContent = $newContent + "`n" + $pageContent
            break
        }
        "bottom" {
            $modifiedContent = $pageContent + "`n" + $newContent
            break
        }
        "topaftertags" {
            $tags = ([regex]::Matches($pageContent, "---\s*\n(.*?\n)*?---", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
            if ($tags.Count -eq 0) {
                Write-Host -ForegroundColor DarkGray "No yaml/tags detected. Skipping..."
            } else {
                if ($tags.Count -eq 1) {
                    $modifiedContent = $pageContent -replace $tags, "$tags`n`n$newContent"
                } else {
                    $modifiedContent = $pageContent -replace $tags[0], "$($tags[0])`n`n$newContent"
                }
            }
            break
        }
        default {
            Write-Host -ForegroundColor Red -BackgroundColor Black "You must specify a valid value for `"`$addWhere`" before executing this script."
            exit
        }
    }

    # Save modified page content
    if ($modifiedContent -ne $null) {
        Set-Content -LiteralPath $_.FullName -Value $modifiedContent -Encoding UTF8
        $updPageCnt++
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) - $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count - $pageCnt) * $avg)
    $time = New-TimeSpan -Seconds ($msLeft / 1000)
    $percent = [Math]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Adding content... ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host "Pages Updated: $updPageCnt"
