###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on scanning each page for Markdown links, images, and templates, then validating
# their syntax and confirming they reference valid files.
#
# Potentially broken resources are exported via CSV at the path in $csvExport.
#
# Optional ($safeLinks): The script can also identify and decode/report any links pointing to a
# "safelinks.protection.outlook.com" URL. These URLs are often copied from emails etc. without
# realizing. You can choose (1) to have the link reported with a note of the decoded target URL,
# or (2) have the script report AND auto-update the link with the decoded URL.
#
# Note: Only relative Markdown links (e.g. "[text](/path/to/item)") are evaluated. Links with
#       URLs are only evaluated for syntax (with the exception for $safeLinks). HTML anchor
#       (e.g., <a>) and image (e.g., <img>) tags are ignored entirely.
#
# Note: If you see red error messages or if the script unexpectedly hangs for an extended time,
#       there are likely syntax errors with parenthesis/bracks ("()" and "[]") that are causing
#       unexpected issues with the RegEx patterns. Try running the page through an online syntax
#       highlighter then trying again.
#
# Note: False positives may appear in the exported CSV, and are expected to a certain degree.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/broken-resources.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required Variables  ##
##########################
$gitRoot = ""     # Local cloned repository (e.g., "<drive>:\path\to\repo")
$csvExport = ".\BrokenResources.csv"   # Where to export the CSV (e.g., "<drive>:\path\to\file.csv")
$safeLinks = 1    # 0=Ignore, 1=Report; 2=Modify; Should Outlook "safelinks" be evaluated? (see Summary above)



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Function expands reference in event file/path contains parenthesis (handles multiples)
function expandRef ($pageContent, $curRef, $encapsulated) {
    $openCurve = ($curRef.ToCharArray() | where { $_ -eq "(" }).Count
    $closeCurve = ($curRef.ToCharArray() | where { $_ -eq ")" }).Count

    $openSquare = ($curRef.ToCharArray() | where { $_ -eq "[" }).Count
    $closeSquare = ($curRef.ToCharArray() | where { $_ -eq "]" }).Count
    
    # Parentheses    
    if ($openCurve -ne $closeCurve) {
        if ($encapsulated) {
            $expanded = [regex]::Matches($pageContent, "(" + [regex]::Escape($curRef) + ")[^\)]*\)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        } else {
            $expanded = [regex]::Matches($pageContent, "(?<=\[[^\]]*\]\s*\()(" + [regex]::Escape($curRef) + ")\)[^\)\s]*((?=(\s=(\d)*x(\d)*)?\))|(?=\s(`"|')[^`"']*(`"|')\)))", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        }
        $expanded | ForEach-Object {
            expandRef $pageContent $_ $encapsulated
        }
    }

    # Square brackets    
    if ($openSquare -ne $closeSquare -and -not $expanded) {
        $expanded = [regex]::Matches($pageContent, "(" + [regex]::Escape($curRef) + ")[^\]]*\][^\(]*\([^\)]*\)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        $expanded | ForEach-Object {
            expandRef $pageContent $_ $encapsulated
        }
    }

    if ($openCurve -eq $closeCurve -and $openSquare -eq $closeSquare) {
            return $curRef
    }
}

# Function outputs broken references to CSV file
function exportCSV ($pageDir, $pageName, $ref, $note) {
    $exportRow = [pscustomobject]@{
        "DirectoryName" = $pageDir
        "PageName" = $pageName
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

    # Look for link/image syntax errors
    if ($pageContent -match "(!\s*)?\[[^\]]*\]\s*\([^\)]*\)(\s*\]\s*\([^\)]*\))?") {
        $linksImages = [regex]::Matches($pageContent, "(!\s*)?\[[^\]]*\]\s*\([^\)]*\)(\s*\]\s*\([^\)]*\))?", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        $linksImages | ForEach-Object {
            # Check for open brackets
            $openCurve = ($_.ToCharArray() | where { $_ -eq "(" }).Count
            $closeCurve = ($_.ToCharArray() | where { $_ -eq ")" }).Count
            $openSquare = ($_.ToCharArray() | where { $_ -eq "[" }).Count
            $closeSquare = ($_.ToCharArray() | where { $_ -eq "]" }).Count

            if ($openCurve -ne $closeCurve -or $openSquare -ne $closeSquare) {
                $expRef = expandRef $pageContent $_ $true
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

            # Check for unwanted spaces
            if ($curRef -match "((?<=\])\s+(?=\())|((?<=!)\s+(?=\[))") {
                Write-Host -ForegroundColor Cyan "Broken reference: $curRef"
                # Export to CSV
                $note = "Syntax: Check for improper spacing."
                exportCSV $pageDir $pageName $curRef $note
            }
        }
    }

    # Look for template syntax errors
    if ($pageContent -match "^:{3}\s*template\s*[^:]*:{3}$") {
        $templates = [regex]::Matches($pageContent, "^:{3}\s*template\s*[^:]*:{3}$", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        $templates | ForEach-Object {
            # Check for missing spaces
            if ($_ -match "(^:{3}(\ |\t)*template[^\s])|(^:{3}\ *\n\ *template)|(^:{3}[^\n]*:{3})") {
                Write-Host -ForegroundColor Cyan "Broken reference: $curRef"
                # Export to CSV
                $note = "Syntax: Check for improper spacing and line breaks."
                exportCSV $pageDir $pageName $curRef $note
            }
        }
    }

    # Validate link/image/template filepaths
    if ($pageContent -match "(?<=\[[^\]]*\]\s*\()[^\)\s]*((?=(\s+=(\d)*x(\d)*\s*)?\))|(?=(\s+(`"|`')[^`"`']*(`"|`')\s*)?\)))*|((?<=:::\s*template\s*)[^\s]*)|(?<=\[[^\]]*\]\s*\([^\)]*\)\s*[^\]]*\]\s*\()[^\)]*(?=\))") {
        $refs = [regex]::Matches($pageContent, "(?<=\[[^\]]*\]\s*\()[^\)\s]*((?=(\s+=(\d)*x(\d)*\s*)?\))|(?=(\s+(`"|`')[^`"`']*(`"|`')\s*)?\)))*|((?<=:::\s*template\s*)[^\s]*)|(?<=\[[^\]]*\]\s*\([^\)]*\)\s*[^\]]*\]\s*\()[^\)]*(?=\))", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
        # Parse references
        $refs | ForEach-Object {
            $curRef = ""
            # Check for parentheses in reference
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
                # Ignored/skipped items (email, placeholders, UNC, etc.)
                { $curRef -match "(mailto:|file:|<|>|@|\\\\)" -or $curRef -eq $null } {
                    # Skip to next iteration of loop
                    break
                }

                # URLs
                { $curRef -match "https?:" } {
                    # Outlook SafeLinks
                    if ($safeLinks -gt 0 -and $curRef -match "(https?://(\w|\d)+\.safelinks\.protection\.outlook\.com/)") {
                        # Extract URI
                        $uri = [regex]::Matches($curRef,"(?<=url=)[^&]*", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
                        # Reverse URL encoding
                        $decodedUri = [System.Uri]::UnescapeDataString($uri)
                        # Modify ref in link
                        if ($safeLinks -eq 2) {
                            # Edit link in page content
                            $pageContent = $pageContent -ireplace [regex]::Escape($curRef), $decodedUri
                            # Save edited content
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
                        # Skip to next iteration of loop
                        break
                    }
                }

                # Jump links
                { $curRef -match "^#" } {
                    $jumpText = [System.Uri]::UnescapeDataString($curRef)
                    $jumpText = $jumpText.Replace("#", "").Replace("---", " - ")
                    $jumpTextEsc = [regex]::Escape($jumpText)
                    $jumpTextPattern = $jumpTextEsc -replace "(?<=[^\s])-(?=[^\s])", "(-|\s)"
                    $jumpLinks = [regex]::Matches($pageContent,$jumpTextPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
                    if ($jumpLinks.Count -eq 0) {
                        Write-Host -ForegroundColor Cyan "Broken reference: $curRef"
                        # Export to CSV
                        $note = "Jump link not found in page contents"
                        exportCSV $pageDir $pageName $curRef $note
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

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count – $pageCnt) * $avg)
    $time = New-TimeSpan –Seconds ($msLeft / 1000)
    $percent = [MATH]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Scanning for borken resources ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Potential Broken References: $brokenCnt"
