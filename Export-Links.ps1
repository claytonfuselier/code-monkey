###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on parsing .md files for URLs with a certain domain (and/or sub domain) and recording every instance
# in a CSV. Using a wildcard to find "all" URLs is not (currently) supported; a domain must be provided.
#
# Note: The script accounts for plaintext and HTML-encoded URLs, as well as HTTP and HTTPS.
# Note: Setting $allsubs to "1" will match any sub-domain (relative to $domain), at any depth. 
#       Example: $domain="example.com" and $allsubs=1, will match on example.com, x.example.com, y.x.example.com, etc.
#       Example: $domain="sub.example.com" and $allsubs=0, will ONLY match on sub.example.com
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/Export-Links.ps1
# Help: https://github.com/claytonfuselier/KM-Scripts/wiki



##########################
##  Required variables  ##
##########################
$gitroot = ""      # Local cloned repository (e.g., "<drive>:\path\to\repo")
$exportfile = ""   # Where to export the CSV (e.g., "<drive>:\path\to\file.csv")
$domain = ""       # Domain/FQDN to search for (e.g., "sub.example.com")
$allsubs = 0       # 0 or 1. See note in "Summary" above.



####################
##  Begin Script  ##
####################
$scriptstarttime = Get-Date
$pagecnt = 0

# Get pages
$pages = Get-ChildItem -Path $gitroot -Recurse -Filter "*.md" -File

# Parse pages
$pages | ForEach-Object {
    $pagename = $_.Name
    $pagepath = ($_.Directory.FullName).Replace($gitroot, "")
    Write-Host "$pagepath\$pagename"

    # Get page content
    $pagecontent = Get-Content -LiteralPath $_.FullName -Encoding UTF8

    # Parse each line
    $line = 1
    $pagecontent | ForEach-Object {
        # Check if line contains a match
        if ($_ -match $domain) {

            # Set RegEx pattern                       
            if ($allsubs) {
                $urlRegex = 'https?(:\/\/|%3A%2F%2F)(?:([a-z]|[0-9]|\-)*\.)*' + [regex]::Escape($domain) + '(\/|%2F)[^)\]}\s>]*'
            } else {
                $urlRegex = 'https?(:\/\/|%3A%2F%2F)' + [regex]::Escape($domain) + '(\/|%2F)[^)\]}\s>]*'
            }


            # Get all matches in the line (accounts for potentially multiple matches per line)
            $urls = [regex]::Matches($_, $urlRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
            if ($urls) {
                foreach ($url in $urls) {
                    $resultsrow = [pscustomobject]@{
                        "Path" = $pagepath
                        "PageName" = $pagename
                        "Line Number" = $line
                        "URL" = $url
                    }
                    $resultsrow | Export-Csv -Path $exportfile -NoTypeInformation -Append
                    Write-Host -ForegroundColor Yellow "Found Link"
                }
            }
        }
        $line++
    }

    # Progress bar
    $pagecnt++
    $avg = ((Get-Date) - $scriptstarttime).TotalMilliseconds / $pagecnt
    $msleft = (($pages.Count - $pagecnt) * $avg)
    $time = New-TimeSpan -Seconds ($msleft / 1000)
    $percent = [Math]::Round(($pagecnt / $pages.Count) * 100, 2)
    Write-Progress -Activity "Searching... ($percent %)" -Status "$pagecnt of $($pages.Count) total pages - $time" -PercentComplete $percent
}
