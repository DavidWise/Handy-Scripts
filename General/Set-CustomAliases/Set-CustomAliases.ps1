param(
    [string] $csvFile,
    [switch] $verbose,
    [switch] $force
)


function Tell([string] $message, [System.ConsoleColor] $ForeGroundColor, [System.ConsoleColor] $BackgroundColor, [switch] $NoNewLine) {

    if (-not $verbose.IsPresent) { return }

    $WHargs = @{
        Object=$message;
        NoNewLine=$NoNewLine.IsPresent
    }

    if ($ForegroundColor -ne $null) { $WHargs.ForeGroundColor = $ForegroundColor }
    if ($BackgroundColor -ne $null) { $WHargs.BackgroundColor = $BackgroundColor }

    write-host @WHargs
}


function ResolvePath([string] $basePath, [string] $relPath) {
    ## TODO: Need to ensure that this always returns the path with or without a trailing slash

    if ([string]::IsNullOrWhiteSpace($basePath) -and [string]::IsNullOrWhiteSpace($relPath)) { return $null }
    if ([string]::IsNullOrWhiteSpace($basePath)-eq $false -and [string]::IsNullOrWhiteSpace($relPath)) { return $basePath }

    $newPath = $basePath

    if ($relPath.StartsWith(".")) {
        $newPath = [IO.Path]::Combine($basePath, $relPath)
        $tempPath = [IO.FileInfo]::new($newPath)
        $newPath = $tempPath.FullName
    } else {
        $newPath = $relPath
    }
    $newPath

    
}


function SetAlias([string] $key, [string] $path) {
    $result = $null

    if ([IO.File]::Exists($path)) {
        $alias = get-alias $key -ErrorAction SilentlyContinue

        if ($force.IsPresent -or $alias -eq $null -or $alias.Definition -ne $path) {

            if ($force.IsPresent -and $alias -ne $null) {
                Tell "removing- " -ForegroundColor Magenta -NoNewLine
                Remove-Item "alias:\$key"
            }
            $aliasArgs = @{Name = $key; Value = $path; }
            Set-Alias @aliasArgs -Option AllScope -Scope Global
        }

        $result = $path
    }

    $result
}


function BuildAliases([string] $pathToCSV) {
    $csvDir = ([IO.fileinfo]::new($pathToCSV)).Directory
   
    $aliasList = Import-Csv -Path $pathToCSV
    Tell "Configuring custom aliases... " -ForegroundColor Green

    $aliasList | % {
        $key = $_.Name
        $path = ResolvePath $csvDir.FullName $_.Path

        Tell "   $key" -NoNewline -ForegroundColor Cyan
        Tell " = " -NoNewline -ForegroundColor Gray

        $newAlias = SetAlias $key $path

        if ($newAlias -eq $null) {
            Tell $path -ForegroundColor Yellow -NoNewline
            Tell " - path does not exist." -ForegroundColor Red
        } else {
            Tell $path -ForegroundColor Green
        }
    }
}


function GetCSVFullPath([string] $passedCSVName) {
    $scriptDir = (get-location).Path

    ResolvePath $scriptDir $passedCSVName
}


function DoAction([string] $csvFileInfo) {
    $csvFullPath = GetCSVFullPath $csvFileInfo


    if ([IO.File]::Exists($csvFullPath)) {
        BuildAliases $csvFullPath
    } else {
        Write-Error "Alias CSV file '$csvFullPath' does not exist"
    }
}


if ([string]::IsNullOrWhiteSpace($csvFile) -eq $false) { DoAction $csvFile }