###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on parsing .md files for HTML image tags that are wrapped inside HTML anchor (link) tags
# (e.g., "<a...><img...></a>") and taking one of three actions below.
#
# In other words, taking HTML embedded images that link to themselves when clicked, and modifying how
# they behave or are embedded.
#
# Actions: 1 - Unwrap and convert image to markdown.   Ex: "![AltText](/path/to/image)"
#          2 - Unwrap but leave image as HTML.         Ex: "<img...>"
#          3 - Convert wrap and image to markdown.     Ex: "[![AltText](/path/to/image)](URL-to-image)"
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/unwrap-images.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required variables  ##
##########################
$gitRoot = ""      # Local cloned repository (e.g., "<drive>:\path\to\repo")
$action = 1        # Action Options:
                      # 1: Unwrap and convert image to markdown
                      # 2: Unwrap but leave image as HTML
                      # 3: Convert wrap and image to markdown



####################
##  Begin Script  ##
####################
$scriptStartTime = Get-Date


# Get all pages
$pages = Get-ChildItem -Recurse $gitRoot -Include *.md | where {! $_.PSIsContainer}


# Parse each page
$pageCnt = 0
$editedPages = 0
$totalEdits = 0
$pages | ForEach-Object {
    # Output current page
    $_.FullName.Replace("$gitRoot","") | Write-Host

    # Get contents of page
    $pageContent = Get-Content -Encoding UTF8 -LiteralPath $_.FullName

    # Check for HTML links wrapped around HTML image tags
    if($pageContent -match "<a[^>]*><img[^>]*><\/a>"){
        # Get all wrapped images
        $wrappedImages = [regex]::Matches($pageContent, "<a[^>]*><img[^>]*><\/a>", [Text.RegularExpressions.RegexOptions]::IgnoreCase)

        # Parse each instance
        $wrappedImages | ForEach-Object{
            # Get pre-spacing
            $curWrappedImage = $_
            $preSpace = ""
            $pageContent | ForEach-Object{
                if($_ -match [regex]::Escape($curWrappedImage)){
                    $preSpace = ([regex]::Matches($_, "^(\t| )*(?=.*" + [regex]::Escape($curWrappedImage) + ")", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                }
            }

            # Isolate anchor tag and get url
            $link = [regex]::Matches($_, "<a[^>]*>", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $linkHref = [regex]::Matches($link, "href=(`"|')?[^`"'\s]*(`"|')?", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $linkUrl = $linkHref.Value.Replace("href=","").Replace("`"","")

            # Isolate img tag
            $img = ([regex]::Matches($_, "<img[^>]*>", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value

            # Get and parse img attributes
            $imgAttribs = ([regex]::Matches($img, "(?<=\s)\w*=[^`"']*`"[^`"']*`"", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
            $imgAttribs | ForEach-Object{
                $curAttrib = $_
                $altText = $null
                $widthSize = $null
                $heightSize = $null

                # Split attribute
                $attribName = $_.Split("=")[0]
                $attribValue = $_.Split("=")[1]

                # Process attribute
                switch ($attribName) {
                    "src" {
                        $imgSrcUrl = $curAttrib.Replace("src=","").Replace("`"","") + "&download=false&resolveLfs=true&%24format=octetStream"
                        $imgPath = ([regex]::Matches($imgSrcUrl, "path=[^\s&`"]*", [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
                        $fixedPath = $imgPath.Replace("path=","").Replace("%2f","/").Replace("%2F","/")
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

            # Format html attributes
            $htmlAttrib = "src=`"$imgSrcUrl`""
            if($altText){
                $htmlAttrib += " alt=`"$altText`""
            }
            if($widthSize){
                $htmlAttrib += " width=`"$widthSize`""
            }
            if($heightSize){
                $htmlAttrib += " height=`"$heightSize`""
            }

            # Format markdown attributes
            if($widthSize -and $heightSize){
                $mdImgSrc = "$fixedPath =$widthSize"+"x"+"$heightSize"
            }
            if($widthSize -and -not$heightSize){
                $mdImgSrc = "$fixedPath =$widthSize"+"x"
            }
            if(-not$widthSize -and $heightSize){
                $mdImgSrc = "$fixedPath =x$heightSize"
            }

            # Create new replacement line
            switch ($action) {
                1{
                    $newLine = "`n`n$preSpace![$altText]($mdImgSrc)"
                }
                2{
                    $newLine = "<img $htmlAttrib>"
                }
                3{
                    $newLine = "`n`n$preSpace[![$altText]($mdImgSrc)]($imgSrcUrl)"
                }
            }

            # Replace content
            $pageContent = $pageContent -replace [Regex]::Escape("$curWrappedImage"), $newLine
            Write-Host -ForegroundColor Cyan "Updated image..."
            $updated = $true
            $totalEdits++
        }
    }

    # Save modified page content
    if($updated){
        Set-Content -Encoding UTF8 -LiteralPath $_.FullName -Value $pageContent
        Write-Host -ForegroundColor Yellow "Saved!"
        $updated = $false
        $editedPages++
    }

    # Progress bar
    $pageCnt++
    $avg = ((Get-Date) – $scriptStartTime).TotalMilliseconds/$pageCnt
    $msLeft = (($pages.Count–$pageCnt)*$avg)
    $time = New-TimeSpan –Seconds ($msLeft/1000)
    $percent = [MATH]::Round(($pageCnt/$pages.Count)*100,2)
    Write-Progress -Activity "Unwrapping Images ($percent %)" -Status "$pageCnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}

Write-Host -ForegroundColor Yellow "Pages updated: $editedPages"
Write-Host -ForegroundColor Yellow "Lines updated: $totalEdits"
