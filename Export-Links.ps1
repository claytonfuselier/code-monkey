###############
##  Summary  ##
###############
# Intended use is on CodeWiki pages in a locally cloned Azure DevOps (or similar local repository).
# Focus is on parsing .md files for URLs with a certain domain name and recording every instance in a CSV. Using a 
# wildcard to find "all" URLs is not (currently) supported; a domain must be provided.
#
# Note: The script accounts for plaintext and HTML-encoded URLs, as well as HTTP and HTTPS.
#
# Source: https://github.com/claytonfuselier/KM-Scripts/blob/main/Export-Links.ps1
# Help: https://github.com/claytonfuselier/KM-Scripts/wiki



##########################
##  Required variables  ##
##########################
$gitroot = ""      # Local cloned repository (e.g., "C:\Users\<username>\git\<repo>")
$exportpath = ""   # Where to export the CSV (e.g., "C:\Users\<username>\Documents")
$domain = ""       # Domain/FQDN to search for (e.g., "sub.example.com")



####################
##  Begin Script  ##
####################
$scriptstarttime = Get-Date
$pagecnt = 0

# Get pages
$pages = Get-ChildItem -Path $gitroot -Recurse | where { $_.Extension -eq ".md" }

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
            # Get all matches in the line (accounts for potentially multiple matches per line)
            $urls = [regex]::Matches($_, 'https?(:\/\/|%3A%2F%2F)' + $domain + '(\/|%2F)[^)\]}\s>]*', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
            $urls | ForEach-Object {

                # Export results
                $resultsrow = New-Object psobject
                $resultsrow | Add-Member -Type NoteProperty -Name "Path" -Value $pagepath
                $resultsrow | Add-Member -Type NoteProperty -Name "PageName" -Value $pagename
                $resultsrow | Add-Member -Type NoteProperty -Name "Line Number" -Value $line
                $resultsrow | Add-Member -Type NoteProperty -Name "URL" -Value $_
                $resultsrow | Export-Csv -Path "$exportpath\Links.csv" -NoTypeInformation -Append
                Write-Host -ForegroundColor Yellow "Found Link"
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
