###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
#
# Focus is on parsing .md files for HTML image tags that are wrapped inside HTML anchor (link) tags
# (e.g., "<a...><img...></a>") and taking one of three actions below.
#
# Actions: 1 - Unwrap and convert image to markdown. Ex: "![filename](/path/to/image)"
#          2 - Unwrap but leave as HTML.             Ex: "<img...>"
#          3 - Convert wrap and image to markdown.   Ex: "[![filename](/path/to/image)](URL-to-image)"
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
    $updated = $false
    $_.FullName.Replace("$gitRoot","") | Write-Host

    # Get contents of page
    $pageContent = Get-Content -Encoding UTF8 -LiteralPath $_.FullName


    # Check for HTML links wrapped around HTML image tags
    if($pageContent -match "<a\s.+<img.+\/a>"){
        # Get all wrapped images
        $wrappedImages = [regex]::Matches($pageContent, "<a[^>]*><img[^>]*><\/a>", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        # Parse each instance
        $wrappedImages | ForEach-Object{
            # Get img path
            $img = [regex]::Matches($_, '<img[^>]*>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $imgSrc = [regex]::Matches($img, 'src=[^\s]+', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $imgSrcUrl = $imgSrc.Value.Replace("src=","").Replace("`"","")
            $imgPath = ([regex]::Matches($imgSrc, 'path=[^\s&"]*', [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value

            # Fix path
            $fixedPath = $imgPath.Replace("path=","").Replace("%2f","/").Replace("%2F","/")

            # Get filename
            $fileName = ([regex]::Matches($fixedPath, '[^\/]+\.\w{3,4}$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value

            # Take $action and create replacement line
            switch ($action) {
                {$_ -le 1} {$newLine = "![$fileName]($fixedPath)"}
                2 {$newLine = "<img $imgSrc>"}
                3 {$newLine = "[![$fileName]($fixedPath)]($imgSrcUrl)"}
            }
            $pageContent = $pageContent -replace [Regex]::Escape("$_"), $newLine
            Write-Host -ForegroundColor Cyan "Updated image..."
            $updated = $true
            $totalEdits++
        }
    }
    
    # Save modified page content
    if($updated){
        Set-Content -Encoding UTF8 -LiteralPath $_.FullName -Value $pageContent
        Write-Host -ForegroundColor Yellow "Saved $($_.FullName.Replace($gitRoot+"\",''))!"
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
Write-Host -ForegroundColor Yellow "Image links updated: $totalEdits"
