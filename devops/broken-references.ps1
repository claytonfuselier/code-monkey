###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on scanning each page for Markdown links/images and template references, then confirming
# the reference points to a valid file.
#
# Note: Only relative Markdown links are evaluated. Links using URLs or HTML tags are not validated.
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/broken-resources.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""     # Local cloned repository (e.g., "<drive>:\path\to\repo")
$csvExport = ".\BrokenReferences.csv"   # Where to export the CSV (e.g., "<drive>:\path\to\file.csv")



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Function expands reference in event file/path contains parenthesis (handles multiples)
function expandRef ($pageContent, $curRef, $dirName, $pageName) {
    $broken = $false
    $open = ($curRef.ToCharArray() | where { $_ -eq "(" }).Count
    $close = ($curRef.ToCharArray() | where { $_ -eq ")" }).Count
    
    if ($open -ne $close -and $Global:skipRef -notcontains $curRef) {
        $Global:skipRef += $curRef
        $dblCheckRef = [regex]::Matches($pageContent, "(?<=\[[^\]]*\]\s*\()(" + [regex]::Escape($curRef) + ")\)[^\)\s]*(?=(\s=(\d)*x(\d)*)?\))", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        $dblCheckRef | ForEach-Object {
            expandRef $pageContent $_ $dirName $pageName
        }
    }

    if ($open -eq $close) {
        $dblCheckPath = "$gitRoot" + "\" + $curRef.Replace("/","\")
        if (-not (Test-Path -LiteralPath $dblCheckPath -ErrorAction SilentlyContinue)){
            Write-Host -ForegroundColor Cyan "(expandRef) Broken reference: $curRef"
            # Export to CSV
            exportCSV $dirName $pageName $curRef
            $brokenCnt++
        }
    }
}

# Function outputs broken references to CSV file
function exportCSV ($dirName, $pageName, $ref) {
    $exportRow = [pscustomobject]@{
        "DirectoryName" = $dirName
        "Name" = $pageName
        "BrokenRef" = $ref
    }
    $exportRow | Export-Csv -Path $csvExport -NoTypeInformation -Append
}


# Get pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File

# Parse each page
$pageCnt = 0
$brokenCnt = 0
$pages | ForEach-Object {
    $dirName = $_.DirectoryName.Replace($gitRoot,"").Replace("\","/")
    $pageName = $_.Name
    $skipRef = @()
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Get contents of page
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Look for references
    if ($pageContent -match "(?<=\[[^\]]*\]\s*\()(?!http)[^\)\s]*(?=(\s=(\d)*x(\d)*)?\))|((?<=:::\s*template\s*)[^\s]*)") {
        $refs = [regex]::Matches($pageContent, "(?<=\[[^\]]*\]\s*\()(?!http)[^\)\s]*(?=(\s=(\d)*x(\d)*)?\))|((?<=:::\s*template\s*)[^\s]*)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        # Parse references
        $refs | ForEach-Object {
            # Check if reference should be ignored
             if ($_ -match "(http|mailto|#|<|>|@|\\\\)" -or $_ -eq $null) {
                # Skip to next reference
                return
            }

            # Check for parenthesis
            if ($_ -like "*(*") {
                # Skip if reference is duplicate on this page
                if ($skipRef -notcontains $_) {
                    expandRef $pageContent $_ $dirName $pageName
                    # Skip to next reference
                }
                return
            }

            # Validating Reference
            $checkPath = "$gitRoot" + "\" + $_.Replace("/","\")
            if (-not (Test-Path -LiteralPath $checkPath -ErrorAction SilentlyContinue)){
                Write-Host -ForegroundColor Cyan "Broken reference: $_"
                # Export to CSV
                exportCSV $dirName $pageName $_
                $brokenCnt++
            }
        }
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds/$pageCnt
    $msLeft = (($pages.Count–$pageCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msLeft/1000)
    $percent = [MATH]::Round(($pageCnt/$pages.Count)*100,2)
    Write-Progress -Activity "Scanning for borken resources ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Potential Broken References: $brokenCnt"
