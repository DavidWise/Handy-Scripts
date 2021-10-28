param(
    [string] $find= "report.txt",
    [string] $folder = "C:\Dev\SedonaOffice\Unified",
    [string] $csv = $null
)

$ci = [stringComparison]::InvariantCultureIgnoreCase

$ignoreFolders = "obj;bin;packages;node_modules;.git;.vs;.vscode;.artifacts"
$ignoreFilesOfType = "dll;exe;pdb;bin;dsr;frx;pcx;pdf;jpg;png;gif;pdn;bmp"

$ignoreFoldersMapped = $ignoreFolders.split(";", [StringSplitOptions]::RemoveEmptyEntries) | % { "*\$($_)"; "*\$($_)\*" }
$ignoreFilesOfTypeMapped = $ignoreFilesOfType.split(";", [StringSplitOptions]::RemoveEmptyEntries) | % { ".$($_)" }

$pctcomplete = 0

function IgnoreFile([System.IO.FileInfo] $info) {
    $ignore = $false

    $ignoreFoldersMapped | % {
        if ($info.DirectoryName -like $_) { $ignore = $true }
    }

    if ($ignore -eq $false) {
        $ignoreFilesOfTypeMapped | % {
            if ($info.Extension -eq $_) {
                $ignore = $true
            }
        }
    }


    $ignore
}


function ResolveCSVPath([string] $path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }

    $testPath = $path
    if ($path.StartsWith("\\") -eq $false -and $path.Substring(2,1) -ne ":") {
        $testPath = Join-Path (Get-Location).Path $path
    }

    if ((test-path $testPath) -eq $true) {
        Remove-Item $testPath
    }

    $testPath
}

function FindInFile([System.IO.FileInfo] $info, [string] $contentToFind ) {
    Write-Progress -Activity "Searching" -Status $info.FullName -PercentComplete $pctcomplete
    $content = Get-Content $info.FullName

    $obj = $null
    $curLine = 0

    $content | % {
        $matchPos= $_.IndexOf($contentToFind, $ci)

        if ($matchPos -ge 0) {
            if ($obj -eq $null) {
                $obj = New-Object psobject
                $obj | Add-Member -MemberType NoteProperty -Name "FullName" -Value $info.FullName
                $obj | Add-Member -MemberType NoteProperty -Name "Matches" -Value @()
            }

            $matchItem = New-Object psobject
            $matchItem | Add-Member -MemberType NoteProperty -Name "Line" -Value $curLine
            $matchItem | Add-Member -MemberType NoteProperty -Name "Position" -Value $matchPos
            $matchItem | Add-Member -MemberType NoteProperty -Name "Text" -Value $_

            $obj.Matches += $matchItem
        }
        $curLine++
    }
    if ($obj -ne $Null) { $obj }
}


function WriteCSVFile($items, [string] $path) {
    $csvFile = ResolveCSVPath $csv 
    if ($csvFile -eq $null) { return }

    Write-Host "Writing CSV file - $csvFile" -ForegroundColor Green
    $foundItems |Select -ExpandProperty matches | Export-csv "$($csvFile)" -NoTypeInformation

    $flatItems = $foundItems | % {
        $fullName = $_.FullName
        $_.Matches | % { 
            $matchItem = New-Object psobject
            $matchItem | Add-Member -MemberType NoteProperty -Name "FullName" -Value $fullName
            $matchItem | Add-Member -MemberType NoteProperty -Name "Line" -Value $_.Line
            $matchItem | Add-Member -MemberType NoteProperty -Name "Position" -Value $_.Position
            $matchItem | Add-Member -MemberType NoteProperty -Name "Text" -Value $_.Text
            $matchItem
        }
    }

    $flatItems | Export-CSV $csvFile -NoTypeInformation
}




pushd $folder
$allFiles = gci $folder\* -Recurse -File

$filePos = 0
$foundItems = $allFiles | % {
    $ignore = IgnoreFile $_ 
    #Write-Host "$($ignore) - $($_.FullName)"

    $filePos++

    $pctcomplete = 100* ($filepos / $allFiles.Length)
    Write-Progress -Activity "Searching" -Status "Overall" -PercentComplete $pctcomplete

    if ($ignore -eq $false) {
        #Write-Host "." -ForegroundColor Green -NoNewline
        #Write-Host "Searching... " -ForegroundColor Green -NoNewline
        #Write-Host $_.FullName -ForegroundColor Yellow
        $match = FindInFile $_ $find

        if ($match -ne $null) {
            #Write-Host "*" -ForegroundColor Yellow
            $match
        }
    } else {
        #Write-Host "." -NoNewline -ForegroundColor Gray
    }
}

popd

WriteCSVFile $foundItems $csv

$foundItems 
