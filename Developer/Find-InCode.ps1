[cmdletbinding()]
param(
    [string] $find = "class",
    [string] $folder = "D:\dev\Github\DWGitsh",
    [string] $ignoreFolders = "obj;bin;packages;node_modules;.git;.vs;.vscode;.artifacts",
    [string] $ignoreFilesOfType = "dll;exe;pdb;bin;dsr;frx;pcx;pdf;jpg;png;gif;pdn;bmp",
    [string] $csv = $null,
    [switch] $matchCase,
    [switch] $quiet
)

$pctcomplete = 0

$data = @{
    "FindText" = $find;
    "Folder" = $folder;
    "CaseSensitivity" = [stringComparison]::InvariantCultureIgnoreCase;
    "IgnoreFolders" = @()
    "IgnoreFilesOfType" = @()
}

function WriteHost([string] $message, [System.ConsoleColor] $ForegroundColor,[System.ConsoleColor] $BackgroundColor, [switch] $NoNewLine) {
    if ($quiet.IsPresent) { return }

    $writeArgs = @{ 
        "Object" = $message;
        "NoNewLine" = $NoNewLine.IsPresent;
        "ForegroundColor" = [Console]::ForegroundColor;
        "BackgroundColor" = [Console]::BackgroundColor;
    }

    if ($ForegroundColor -ne $Null) {
        $writeArgs.ForegroundColor = $ForegroundColor
    }

    if ($BackgroundColor -ne $Null) {
        $writeArgs.BackgroundColor = $BackgroundColor
    }

    Write-Host @writeArgs
}

function BuildIgnoreFolders([string] $folderList) {
    if ([string]::IsNullOrWhiteSpace($folderList)) { return @() }

    $folderList.split(";", [StringSplitOptions]::RemoveEmptyEntries) | % { 
        "*\$($_)"; 
        "*\$($_)\*" 
    }
}


function BuildIgnoreFilesOfType([string] $fileTypeList) {
    if ([string]::IsNullOrWhiteSpace($fileTypeList)) { return @() }

    $fileTypeList.split(";", [StringSplitOptions]::RemoveEmptyEntries) | % {
        $curExt = $_.Trim('.')
        ".$($curExt)" 
    }
}


function IgnoreFile([System.IO.FileInfo] $info) {
    $matched = $data.IgnoreFolders | Where-Object { $info.DirectoryName -like $_}   
    if ($null -ne $matched) { return $true }

    $matched = $data.IgnoreFilesOfType | Where-Object { $info.Extension -eq $_ }
    if ($null -ne $matched) { return $true }

    $false
}


function ResolveCSVPath([string] $path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }

    $testPath = $path
    if ($path.StartsWith("\\") -eq $false -and $path.Substring(2,1) -ne ":") {
        $testPath = Join-Path (Get-Location).Path $path
    }

    if ((test-path $testPath -PathType Leaf) -eq $true) {
        Remove-Item $testPath
    }

    $testPath
}


function FindInFile([System.IO.FileInfo] $info, [string] $contentToFind ) {
    Write-Progress -Activity "Searching" -Status $info.FullName -PercentComplete $pctcomplete
    $content = Get-Content $info.FullName

    $obj = $null
    $curLine = 1

    $content | % {
        $matchPos= $_.IndexOf($contentToFind, $data.CaseSensitivity)

        if ($matchPos -ge 0) {
            if ($obj -eq $null) {
                $obj = New-Object psobject
                $obj | Add-Member -MemberType NoteProperty -Name "FullName" -Value $info.FullName
                $obj | Add-Member -MemberType NoteProperty -Name "Matches" -Value @()
            }

            Write-Verbose "   Found match at line: $curLine, position: $matchPos"
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


function WriteResultsToScreen($items) {
    if ($quiet.IsPresent -or $null -eq $items) { return }

    $items | % {
        WriteHost $_.FullName -ForegroundColor Green

        $_.Matches | % {
            $curLine = $_.Text
            $matchText = $data.FindText

            WriteHost ("{0,5} " -f $_.Line) -ForegroundColor Gray -NoNewline
            
            $segLeft = $curLine.substring(0, $_.Position)
            $segRight = $curLine.substring($segLeft.length + $matchText.Length)

            WriteHost $segLeft -ForegroundColor Gray -NoNewline
            WriteHost $matchText -ForegroundColor DarkGray -NoNewline -BackgroundColor White
            WriteHost $segRight -ForegroundColor Gray 
        }
    }
}


function WriteResults($items, [string] $path) {
    $csvFile = ResolveCSVPath $csv 
    if ($csvFile -eq $null) { 
        WriteResultsToScreen $items
        return 
    }

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


function FindTextInCodeFile([string] $findText, [System.IO.FileInfo] $curFile) {
    $ignore = IgnoreFile $curFile 

    if ($ignore -eq $false) {
        Write-Verbose "Searching: $($curFile.FullName)"
        $match = FindInFile $curFile $findText

        if ($match -ne $null) {
            $match
        }
    } else {
        Write-Verbose "(Ignore) : $curFile.FullName"
    }
}


function DetermineStartFolder([string] $curFolder) {
    $result = $curFolder

    if ([string]::IsNullOrWhiteSpace($result)) {
        $result = (Get-Location).Path
    }
    
    if (-not (Test-Path $result)) {
        Write-Error "Folder '$($result)' does not exist"
        exit(9)
    }

    $result
}


function FindTextInSelectedPath([string] $findText, [string] $curFolder) {
    Push-Location $curFolder

    write-verbose "Building files list under: $curFolder"
    $allFiles = Get-ChildItem $curFolder\* -Recurse -File
    
    $filePos = 0
    $foundItems = $allFiles | % {
        $filePos++
    
        $pctcomplete = 100* ($filepos / $allFiles.Length)
        Write-Progress -Activity "Searching" -Status "Overall" -PercentComplete $pctcomplete
    
        FindTextInCodeFile $findText $_
    }
    
    Pop-Location
    
    $foundItems
}


if ([string]::IsNullOrEmpty($find)) {
    Write-Error "A valid text string must be specified for -Find"
    Exit(1)
}

if ($matchCase.IsPresent) { 
    $data.CaseSensitivity = [stringComparison]::InvariantCulture 
}

$data.Folder = DetermineStartFolder $folder

$data.IgnoreFolders = BuildIgnoreFolders $IgnoreFolders
$data.IgnoreFilesOfType = BuildIgnoreFilesOfType $IgnoreFilesOfType


$foundItems = FindTextInSelectedPath $data.FindText $data.Folder

WriteResults $foundItems $csv

$foundItems 
