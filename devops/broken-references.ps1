###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on scanning each page for Markdown links/images and template references, then confirming
# the reference points to a valid file.
#
# safeLinks: (Optional) The script can also identify and report any "safelinks.protection.outlook.com"
# links that are detected. These are often copied from emails without realizing. You can choose (1) to
# have the link reported with a note of the decoded target URL, or (2) have the script report AND
# auto-update the link with the decoded URL.
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
$safeLinks = 1    # 0=Ignore, 1=Report; 2=Modify; Should links Outlook "safelinks" be evaluated? (see Summary above)



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Function expands reference in event file/path contains parenthesis (handles multiples)
function expandRef ($pageContent, $curRef) {
    $open = ($curRef.ToCharArray() | where { $_ -eq "(" }).Count
    $close = ($curRef.ToCharArray() | where { $_ -eq ")" }).Count
    
    if ($open -ne $close) {
        $expanded = [regex]::Matches($pageContent, "(?<=\[[^\]]*\]\s*\()(" + [regex]::Escape($curRef) + ")\)[^\)\s]*((?=(\s=(\d)*x(\d)*)?\))|(?=\s(`"|')[^`"']*(`"|')\)))", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        $expanded | ForEach-Object {
            expandRef $pageContent $_
        }
    }

    if ($open -eq $close) {
            return $curRef
    }
}

# Function outputs broken references to CSV file
function exportCSV ($pageDir, $pageName, $ref, $note) {
    $exportRow = [pscustomobject]@{
        "DirectoryName" = $pageDir
        "Name" = $pageName
        "BrokenRef" = $ref
        "Note" = $note
    }
    $exportRow | Export-Csv -Path $csvExport -NoTypeInformation -Append
    $Global:brokenCnt++
}



# Get pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File

# Parse each page
$pageCnt = 0
$brokenCnt = 0
$pages | ForEach-Object {
    $pageDir = $_.DirectoryName.Replace($gitRoot,"").Replace("\","/")
    $pageName = $_.Name
    $pageFullName = $_.FullName
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
            $curRef = ""
            # Parentheses in reference
            if ($_ -match "\(" ) {
                $expRef = expandRef $pageContent $_

                if ($expRef.Count -gt 1) {
                    $expRef | ForEach-Object {
                        if ($curRef -eq "" -and $skipRef -notcontains $_) {
                            $curRef = $_
                            $skipRef += $curRef
                        }
                    }
                } else {
                    $curRef = $expRef
                }
            } else {
                $curRef = $_
            }

            switch ($curRef) {
                # Ignored/skipped items (email, placeholders, etc.)
                { $curRef -match "(mailto:|file:|<|>|@|\\\\)" -or $curRef -eq $null } {
                    # Skip to next interation of loop
                    break
                }

                # URLs
                { $curRef -match "https?:" } {
                    # Outlook SafeLinks
                    if ($safeLinks -gt 0 -and $curRef -match "(https?://(\w|\d)+\.safelinks\.protection\.outlook\.com/)") {
                        # Extract URI
                        $uri = [regex]::Matches($pageContent,"(?<=url=)[^&]*", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
                        # Reverse URL encoding
                        $decodedUri = [System.Uri]::UnescapeDataString($uri)
                        # Modify ref in link
                        if ($safeLinks -eq 2) {
                            # Edit link in page content
                            $pageContent = $pageContent -ireplace $curRef, $decodedUri
                            # Save edit
                            Set-Content -LiteralPath $pageFullName -Value $pageContent -Encoding UTF8
                            $note = "SafeLinks (AUTO-REPLACED): $decodedUri"
                        } else {
                            # Do not modify ref in link
                            $note = "SafeLinks: $decodedUri"
                        }
                        Write-Host -ForegroundColor Cyan "Broken reference: $curRef"
                        # Export to CSV
                        exportCSV $pageDir $pageName $curRef $note
                        break
                    } else {
                        # Skip to next interation of loop
                        break
                    }
                }

                # Jump links
                { $curRef -match "^#" } {
                    $jumpLinkText = ([System.Uri]::UnescapeDataString($curRef.Replace("#", "").Replace("---", " - "))) -replace "(?<=\w)-(?=\w)", " "
                    $jumpLinks = [regex]::Matches($pageContent,[regex]::Escape($jumpLinkText), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
                    if ($jumpLinks.Count -eq 0) {
                        Write-Host -ForegroundColor Cyan "Broken reference: $curRef"
                        # Export to CSV
                        exportCSV $pageDir $pageName $curRef "Jump Link: `"$jumpLinkText`" not found in page contents"
                    }
                    break
                }

                # Default validation (file based)
                default {
                    $checkPath = "$gitRoot" + $curRef.Replace("/","\")
                    if (-not (Test-Path -LiteralPath $checkPath -ErrorAction SilentlyContinue)){
                        Write-Host -ForegroundColor Cyan "Broken reference: $curRef"
                        # Export to CSV
                        exportCSV $pageDir $pageName $curRef
                    }
                    break
                }
            }
        }
    }

    Write-Host $skipRef

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count – $pageCnt) * $avg)
    $time = New-TimeSpan –Seconds ($msLeft / 1000)
    $percent = [MATH]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Scanning for borken resources ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Potential Broken References: $brokenCnt"
