###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# The focus is on parsing .md files for HTML image tags and modifying their behavior and/or embedding.
# Particular attention is given to HTML images wrapped inside HTML anchor (link) tags
# (e.g., "<a...><img...></a>") and taking one of the three actions below.
#
# Actions: 1 - Unwrap and convert the image to markdown.   Ex: "![AltText](/path/to/image)"
#          2 - Unwrap but leave the image as HTML.         Ex: "<img...>"
#          3 - Convert wrap and image to markdown.         Ex: "[![AltText](/path/to/image)](URL-to-image)"
#
# If $incldPlainImg is set to "1", the script will also modify non-wrapped HTML images to the same format.
#
# Note: The script attempts to maintain the existing tab/indentation to not disrupt the flow or appearance
#       of any content. Be sure to review all changes to ensure they render properly and as desired.
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/modify-images.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required variables  ##
##########################
$gitRoot = ""        # Local cloned repository (e.g., "<drive>:\path\to\repo")
$action = 1          # 1, 2, or 3; See summary above for descriptions of each action.
$incldPlainImg = 1   # 0=No, 1=Yes; Modify non-wrapped images?



####################
##  Begin Script  ##
####################
$scriptStart = Get-Date

# Get all pages
$pages = Get-ChildItem -Path $gitRoot -Filter "*.md" -Recurse -File

# Parse each page
$pageCnt = 0
$editedPages = 0
$totalEdits = 0
$pages | ForEach-Object {
    # Console output for the current page
    Write-Host -ForegroundColor Gray $_.FullName.Replace($gitRoot, "")

    # Get the contents of the page
    $pageContent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Check for HTML image tags
    if ($pageContent -match "<img[^>]*>") {
        if ($incldPlainImg) {
            # Get all HTML images
            $images = [regex]::Matches($pageContent, "(<a[^>]*><img[^>]*(src=)[^>]*><\/a>)|((?<!(<a[^>]*>\s*))<img[^>]*(src=)[^>]*>)", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        } else {
            # Get only wrapped images
            $images = [regex]::Matches($pageContent, "<a[^>]*><img[^>]*(src=)[^>]*><\/a>", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        # Parse each instance
        $images | ForEach-Object {
            # Get pre-spacing
            $curImage = $_
            $preSpace = ""
            $pageContent | ForEach-Object {
                if ($_ -match [regex]::Escape($curImage)) {
                    $preSpace = ([regex]::Matches($_, "^(\t| )*(?=.*" + [regex]::Escape($curImage) + ")", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                }
            }

            # Get and parse attributes
            $imgAttribs = ([regex]::Matches($_, "(?<=\s)\w*=[^`"']*`"[^`"']*`"", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
            $altText = $null
            $widthSize = $null
            $heightSize = $null
            $imgAttribs | ForEach-Object {
                $curAttrib = $_

                # Split attribute
                $attribName = $_.Split("=")[0]
                $attribValue = $_.Split("=")[1]
                
                # Process attribute
                switch ($attribName) {
                    "src" {
                        $imgSrcUrl = $curAttrib.Replace("src=","").Replace("`"","")
                        $domain = ([regex]::Matches($imgSrcUrl, "(?<=https?:\/\/)[^\/]*", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                        
                        # Check if the image URL is hosted in ADO
                        if ($domain -eq "dev.azure.com" -or $domain -like "*.visualstudio.com") {
                            # Process/Modify the image hosted internally in ADO
                            $imgClickUrl = $imgSrcUrl + "&download=false&resolveLfs=true&%24format=octetStream"
                            $imgPath = ([regex]::Matches($imgSrcUrl, "path=[^\s&`"]*", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                            $fixedPath = $imgPath.Replace("path=","").Replace("%2f","/").Replace("%2F","/")
                        } else {
                            # Process/Modify externally hosted images
                            $imgClickUrl = $imgSrcUrl
                            $fixedPath = $imgSrcUrl
                        }
                    }
                    "alt" {
                        $altText = $attribValue.Replace("`"","").Replace("'","")
                    }
                    "width" {
                        $widthSize = ([regex]::Matches($attribValue, "\d+", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                    }
                    "height" {
                        $heightSize = ([regex]::Matches($attribValue, "\d+", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                    }
                }
            }

            # Format HTML attributes
            $htmlAttrib = "src=`"$imgSrcUrl`""
            if ($altText) {
                $htmlAttrib += " alt=`"$altText`""
            }
            if ($widthSize) {
                $htmlAttrib += " width=`"$widthSize`""
            }
            if ($heightSize) {
                $htmlAttrib += " height=`"$heightSize`""
            }

            # Format markdown attributes
            if ($widthSize -and $heightSize) {
                $mdImgSrc = "$fixedPath =$widthSize"+"x"+"$heightSize"
            }
            if ($widthSize -and -not $heightSize) {
                $mdImgSrc = "$fixedPath =$widthSize"+"x"
            }
            if (-not $widthSize -and $heightSize) {
                $mdImgSrc = "$fixedPath =x$heightSize"
            }

            # Create a new replacement line
            switch ($action) {
                1 {
                    $newLine = "`n`n$preSpace![$altText]($mdImgSrc)"
                }
                2 {
                    $newLine = "<img $htmlAttrib>"
                }
                3 {
                    $newLine = "`n`n$preSpace[![$altText]($mdImgSrc)]($imgClickUrl)"
                }
            }

            # Replace content
            $pageContent = $pageContent -replace [Regex]::Escape($_), $newLine
            Write-Host -ForegroundColor Cyan "Updated image..."
            $updated = $true
            $totalEdits++
        }
    }

    # Save the modified page content
    if ($updated) {
        Set-Content -LiteralPath $_.FullName -Value $pageContent -Encoding UTF8
        Write-Host -ForegroundColor Yellow "Saved!"
        $updated = $false
        $editedPages++
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStart).TotalMilliseconds / $pageCnt
    $msLeft = (($pages.Count – $pageCnt) * $avg)
    $time = New-TimeSpan –Seconds ($msLeft / 1000)
    $percent = [MATH]::Round(($pageCnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Unwrapping Images ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Pages updated: $editedPages"
Write-Host -ForegroundColor Yellow "Lines updated: $totalEdits"
