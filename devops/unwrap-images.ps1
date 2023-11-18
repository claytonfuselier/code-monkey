###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on parsing .md files for HTML image tags that are wrapped in HTML anchor tags
# (e.g., "<a...><img...></a>") and unwrapping them, while simultaneously converting them to 
# markdown syntax (e.g., "![filename](/path/to/image)")
#
# Source: https://github.com/claytonfuselier/code-monkey/blob/main/devops/unwrap-images.ps1
# Help: https://github.com/claytonfuselier/code-monkey/wiki



##########################
##  Required variables  ##
##########################
$gitRoot = ""      # Local cloned repository (e.g., "<drive>:\path\to\repo")



####################
##  Begin Script  ##
####################
$scriptStartTime = Get-Date


# Get all pages
$pages = Get-ChildItem -Recurse $gitroot -Include *.md | where {! $_.PSIsContainer}
$pagecnt = 0
$updpagecnt = 0
$updimgcnt = 0


# Parse each page
$pages | ForEach-Object {
    $updated = "false"
    $_.FullName.Replace("$gitroot","") | Write-Host

    # Get contents of page
    $pagecontent = Get-Content -Encoding UTF8 -LiteralPath $_.FullName

    # Check for HTML links wrapped around HTML image tags
    if($pagecontent -match "<a\s.+<img.+\/a>"){
        # Get all wrapped images
#        $wrappedimages = [regex]::Matches($pagecontent, "(<br\/>)*<a[^>]*><img[^>]*><\/a>(<br\/?>)*", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $wrappedimages = [regex]::Matches($pagecontent, "<a[^>]*><img[^>]*><\/a>", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        # Parse each instance
        $wrappedimages | ForEach-Object{
            $img = [regex]::Matches($_, '<img[^>]*>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $imgsrc = [regex]::Matches($img, 'src=[^\s]+', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $path = ([regex]::Matches($imgsrc, 'path=[^\s&"]*', [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
#            Write-Host -ForegroundColor Cyan "origpath: $path"

            # Fixing/Cleaning path
            $fixedpath = $path.Replace("path=","").Replace("%2f","/").Replace("%2F","/")
#            Write-Host -ForegroundColor Green "fixedpath: $fixedpath"

            # Convert to markdown syntax (without wrapped link)
            $filename = ([regex]::Matches($fixedpath, '[^\/]+\.\w{3,4}$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Value
#            $mdimg = "![$filename]($fixedpath)"
            $replacement = "![$filename]($fixedpath)"
            $pagecontent = $pagecontent -replace [Regex]::Escape("$_"), $replacement
            Write-Host -ForegroundColor Cyan "Unwrapped and converted image."
            $updated = "true"
            $updimgcnt++
        }
    }


    # Save modified page content
    if($updated -eq "true"){
        Set-Content -Encoding UTF8 -LiteralPath $_.FullName -Value $pagecontent
        Write-Host -ForegroundColor Yellow "Updated! $($_.FullName)"
        $updpagecnt++
    }


    # Progress bar
    $pagecnt++
    $avg = ((Get-Date) – $scriptstarttime).TotalMilliseconds/$pagecnt
    $msleft = (($pages.Count–$pagecnt)*$avg)
    $time = New-TimeSpan –Seconds ($msleft/1000)
    $percent = [MATH]::Round(($pagecnt/$pages.Count)*100,2)
    Write-Progress -Activity "Unwrapping Images ($percent %)" -Status "$pagecnt of $($pages.Count) total pages - $time" -PercentComplete $percent

}

Write-Host "Unwrapped Images: $updimgcnt ($updpagecnt pages)"
