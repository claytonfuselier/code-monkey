###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repositiory).
#
# Focus is on scanning each page for markdown links/images and template references, then confirming
# the reference points to a valid file.
#
# Note: Only relative markdown links are evaluated. Links via HTMl tags or using URLs are not validated.
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/broken-resources.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""             # Local cloned repository (e.g., "<drive>:\path\to\repo")
$csvExport = ".\BrokenReferences.csv"   # Where to export the CSV (e.g., "<drive>:\path\to\file.csv")



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Get pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File

# Get all files
#$files = Get-ChildItem -Path $gitRoot -Recurse -File

# Parse each page
$pageCnt = 0
$brokenCnt = 0
$pages | ForEach-Object {
    $dirName = $_.DirectoryName.Replace($gitRoot,"").Replace("\","/")
    $pageName = $_.Name
    # Console output for current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot,"")

    # Get contents of page
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Look for references
    if ($pageContent -match "(?<=\[[^\]]*\]\s*\()(?!http)[^\)\s]*(?=(\s=(\d)*x(\d)*)?\))|((?<=:::\s*template\s*)[^\s]*)") {
        $refs = [regex]::Matches($pageContent, "(?<=\[[^\]]*\]\s*\()(?!http)[^\)\s]*(?=(\s=(\d)*x(\d)*)?\))|((?<=:::\s*template\s*)[^\s]*)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        # Parse references
        $refs | ForEach-Object {
            # Skip ref?
            if ($_ -notlike "*http*" -and $_ -notlike "*mailto:*" -and $_ -notlike "*#*" -and $_ -notlike "*<*" -and $_ -notlike "*>*" -and $_ -notlike "*@*" -and $_ -ne "") {
                # Validate file
                $checkPath = "$gitRoot" + "\" + $_.Replace("/","\")
                if (-not (Test-Path -LiteralPath $checkPath -ErrorAction SilentlyContinue) -or $_ -eq $lastRef){
                    # Check for open parenthensis
                    if ($_ -like "*(*") {
                        $dblCheckRef = [regex]::Matches($pageContent, "(" + [regex]::Escape($_) + ")\)[^\)\s]*(?=(\s=(\d)*x(\d)*)?\))", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
                        $dblCheckRef | ForEach-Object {
                            $dblCheckPath = "$gitRoot" + "\" + $_.Replace("/","\")
                            if (-not (Test-Path -LiteralPath $dblCheckPath -ErrorAction SilentlyContinue)){
                                $broken = $true
                            }
                        }
                    } else {
                        $broken = $true
                    }
                }
                if ($broken) {
                    Write-Host -ForegroundColor Cyan "Broken reference: $_"
                    # Export to CSV
                    $exportRow = [pscustomobject]@{
                        "DirectoryName" = $dirName
                        "Name" = $pageName
                        "BrokenRef" = $_
                    }
                    $exportRow | Export-Csv -Path $csvExport -NoTypeInformation -Append
                    $brokenCnt++
                    $broken = $false
                }
            }
            $lastRef = $_
        }
    }
    $lastRef = ""

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds/$pageCnt
    $msLeft = (($pages.Count–$pageCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msLeft/1000)
    $percent = [MATH]::Round(($pageCnt/$pages.Count)*100,2)
    Write-Progress -Activity "Scanning for borken resources ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Potential Broken References: $brokenCnt"
