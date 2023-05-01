param(
    [string] $fileToFind
)




if ($fileToFind -eq $null -or $fileToFind -eq "") {
    write-error "A file name to find is required"
    exit 1
}


$searchPaths = "$((Get-Location).Path);$($env:Path)".split(";") | where { [string]::IsNullOrEmpty($_) -eq $false } | Select -Unique

$fileMask = $fileToFind
#if ($fileMask.IndexOfAny("?*".ToCharArray()) -lt 0) {
#    $fileMask = "$($fileMask)*.*"
#}

#Write-host $fileMask -ForegroundColor Green
$matchFound = $false
$searchPaths | % {
    $curPath = $_
    $matches = [System.IO.Directory]::GetFiles($_, $fileMask)

    if ($matches -ne $null) {
        $matches | % {
            $curMatch = $_
            $item = get-item $curMatch
            Write-Output $item.fullname
            $matchFound = $true
        }
    }
}

if ($matchFound -eq $false) {
    Write-Host "No match found" -ForegroundColor Yellow
}
