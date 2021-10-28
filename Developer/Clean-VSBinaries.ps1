param(
    [string] $solutionFolder = (Get-Location).Path 
)

Write-Host "Cleaning solution items in '$($solutionFolder)'"

if ((Test-Path $SolutionFolder -PathType Container) -eq $false) {
    Write-Error "Specified folder '$($SolutionFolder)' does not exist"
    exit 1
}


$repo = get-item $solutionFolder
$solutionFiles = $repo.GetFiles("*.sln", [System.IO.SearchOption]::TopDirectoryOnly)
if ($solutionFiles.Length -eq 0) {
    Write-Error "No solution (.sln) files found in '$($SolutionFolder)'"
    exit 2
}

$basePath = $repo.FullName
$baseLen = $basePath.length
if ($baseLen -lt 5) {
    Write-Error "The repo base path of $basePath is too short for this command"
    Exit 5
}

$ci = [StringComparison]::InvariantCultureIgnoreCase


function ShouldPurgeFolder([System.IO.DirectoryInfo] $folder, [string] $relativePath) {
    $doPurge = $false

    if ($folder.name -eq "obj" -or $folder.Name -eq "bin") { 
        $parentFiles = $folder.Parent.GetFiles("*.*", [System.IO.SearchOption]::TopDirectoryOnly)

        $proj = $parentFiles | where {$_.Extension.EndsWith("proj", $ci) } | Select FullName
        $doPurge = ($proj -ne $null) 
    }

    $doPurge
}

$dirs= $repo.GetDirectories("*.*", [System.IO.SearchOption]::AllDirectories)


$purgeDirs = $dirs | % {
    $curDir = [System.IO.DirectoryInfo] $_

    $relPath = $curDir.FullName.Substring($baseLen+1)

    $ignore = $false
    if ($relPath -eq ".git" -or $relPath.StartsWith(".git\")) { $ignore = $true }
    if ($relPath -eq "packages" -or $relPath.StartsWith("packages\")) { $ignore = $true }
    if ($relPath -eq ".artifacts" -or $relPath.StartsWith(".artifacts\")) { $ignore = $true }


    if (-not $ignore) {
        if (ShouldPurgeFolder $curDir $relPath) {
            $curDir
        }
    }
}

$purgeDirs | % {
    $curDir = [System.IO.DirectoryInfo] $_

    # extra safety check since we are deleting folders
    if ($curDir.FullName.StartsWith($basePath, $ci)) {
        Write-Host "Removing folder: $($curDir.FullName)" -ForegroundColor Yellow
        $curDir.Delete($true)
    }
}

write-host "Done" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Deleting these files will trigger a Nuget Restore so wait a few for Visual Studio to complete that before building" -ForegroundColor White