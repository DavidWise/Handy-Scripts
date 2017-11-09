param (
    [Parameter(ParameterSetName=’listHosts’)]
    [switch] $list,

    [Parameter(ParameterSetName=’listHosts’)]
    [switch] $full,

    [Parameter(ParameterSetName=’addHosts’)]
    [switch] $add,

    [Parameter(ParameterSetName=’removeHosts’)]
    [switch] $remove,

    [Parameter(ParameterSetName=’addHosts’, Position=0)]
    [Parameter(ParameterSetName=’removeHosts’, Position=0)]
    [string] $HostName,

    [Parameter(ParameterSetName=’addHosts’, Position=1)]
    [Parameter(ParameterSetName=’removeHosts’, Position=1)]
    [string] $IPAddress,

    [Parameter(ParameterSetName=’addHosts’)]
    [switch] $ReplaceIfExists,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $Comment
)

$hosts = "$($env:windir)\System32\drivers\etc\hosts"
$changesMade = $false
$entries = @()

function IsAdministrator
{  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}


function ExitWithMessage([int] $exitCode, [ConsoleColor] $ForegroundColor, [string] $exitMessage, $msgArgs) {
    $newMsg = $exitMessage
    if ($msgArgs -ne $null) { $newMsg = [string]::Format($exitMessage, $msgArgs) }

    write-host $newMsg -ForegroundColor $ForegroundColor
    #$host.SetShouldExit($exitCode)
    $false
    exit $exitCode
}


function NewEntry() {
    $obj = New-Object psobject
    $obj | Add-Member -MemberType NoteProperty -Name "Address" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "Host" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "Comment" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "OriginalValue" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "OutputValue" -Value ""
    $obj | Add-Member -MemberType NoteProperty -Name "IsEntry" -Value $false
    $obj | Add-Member -MemberType NoteProperty -Name "Deleted" -Value $false
    $obj | Add-Member -MemberType NoteProperty -Name "Added" -Value $false
    $obj | Add-Member -MemberType NoteProperty -Name "LineNumber" -Value -1
    
    $obj
}


function GetHostsFile([string] $hostsPath) {
    $hostfile = Get-Content $hosts
    $lineNumber = 0

    $hostfile | % {
        $line = "$_".Replace('`t', " ").Trim()
        $lineNumber++

        $obj = NewEntry

        $obj.OriginalValue = $_.TrimEnd()
        $obj.LineNumber = $lineNumber

        $commentPos = $line.IndexOf("#")
        if ($commentPos -ge 0) {
            $obj.Comment = $line.Substring($commentPos + 1);

            if ($commentPos -eq 0) {
                $line = ""
            } else {
                $line = $line.Substring(0, $commentPos).Trim();
            }
        }


        if ([string]::IsNullOrWhiteSpace($line) -eq $false) {
            $splitPos = $line.IndexOf(" ")

            if ($splitPos -gt 0) {
                $obj.Address = $line.Substring(0, $splitPos).Trim()
                $obj.Host = $line.Substring($splitPos+1).Trim()
                $obj.IsEntry = $true
            }
        }

        $obj
    }
}



function ListEntries($entries) {
    if ($list.IsPresent -eq $false) { return }
    $entries | where {$_.IsEntry} | select Host, Address, Comment | sort Host
}


function AddEntry([string]$newHost, [string] $newIP, [bool] $replace, [string] $addComment) {
    $targetIP = "$newIP".Trim()
    $targetHost = "$newHost".Trim()
    if ([string]::IsNullOrWhiteSpace($targetIP)) { $targetIP = "127.0.0.1" }

    if ([string]::IsNullOrWhiteSpace($targetHost)) { 
        ExitWithMessage 1 -foreColor Red "a host name is required"
    }

    $addEntry = $entries | where { $_.host -eq $targetHost }

    if ($addEntry -ne $null -and $replace -eq $false) {
        ExitWithMessage 3 -ForegroundColor Red  "An entry for that host already exists.  Use the -ReplaceIfExists switch to force it to replace"
    }

    if ($addEntry -eq $null) {
        $addEntry = newEntry
        #$script:entries.Add($addEntry)
        $script:entries += $addEntry
    }

    if ([string]::IsNullOrWhiteSpace($addComment) -eq $false) {
        $addEntry.Comment = $addComment
    }

    $addEntry.Host = $targetHost
    $addEntry.Address = $targetIP
    $addEntry.Added = $true
    $addEntry.IsEntry = $true

    $Script:changesMade = $true
}


function MatchesValue([string] $value1, [string] $value2) {
    $val1 = "$value1".Trim()
    $val2 = "$value2".Trim()

    # both items must have a value in order to be evaluated
    if ([string]::IsNullOrEmpty($val1) -or [string]::IsNullOrEmpty($val2)) { return $false }

    return ($val1 -eq $val2)
}


function RemoveEntry([string]$oldHost, [string] $oldIP, [string] $oldComment) {

    $entries | % {
        $isamatch = (MatchesValue $oldHost $_.Host) -or (MatchesValue $oldIP $_.Address) -or (MatchesValue $oldComment $_.Comment)

        if ($isamatch)  {
            $_.Deleted = $true
            $Script:changesMade = $true
        }
    }
    
}


function WriteHostsFile([string] $hostsPath) {
    if ($changesMade -eq $false) { return }

    $outEntries = $entries | where {$_.Deleted -ne $true }

    $maxHostLen = -1
    $maxIPLen = -1
    $outEntries | % {
        if ("$($_.Host)".length -gt $maxHostLen) { $maxHostLen = "$($_.Host)".length }
        if ("$($_.Address)".length -gt $maxIPLen) { $maxIPLen = "$($_.Address)".length }
    }

    $maxHostLen += 2
    $maxIPLen  += 2

    $outEntries | % {
        $_.OutputValue = $_.OriginalValue
        $outComment = ""
        if ([string]::IsNullOrWhiteSpace($_.Comment) -eq $false) { $outComment = "#" + $_.Comment }
        if ($_.IsEntry -eq $true) {
            $_.OutputValue = [string]::Format("{0, -" + $maxIPLen.ToString() + "} {1, -" + $maxHostLen.ToString() + "} {2}", $_.Address, $_.Host, $outComment).trim()
        }
    }


    $newEntries = $outEntries | % { $_.OutputValue }

    $info = New-Object System.IO.FileInfo($hostsPath)

    $backupFileName = [string]::Format("hosts_{0:yyyyMMddHHmmss}", [DateTime]::Now)

    $bakfile = [System.IO.Path]::Combine($info.DirectoryName, $backupFileName)

    $copied = [System.IO.File]::Copy($hostsPath, $bakfile)

    $newEntries | Out-File $hostsPath -Encoding ascii 

    Write-Host "Changes written successfully" -ForegroundColor Green
}


if ($full.IsPresent) {
    Get-Content $hosts | Write-Output
    exit
}

$entries = GetHostsFile $hosts

if ($list.IsPresent) { 
    ListEntries $entries 
    return
}

$isAdmin = IsAdministrator


if (($add.IsPresent -or $remove.IsPresent) -and $isAdmin -eq $false) {
    ExitWithMessage 2 -ForegroundColor Yellow "Script must be run as Administrator in order to make any changes" 
}

if ($add.IsPresent) {
    AddEntry $HostName $IPAddress $ReplaceIfExists.IsPresent $Comment
}

if ($remove.IsPresent) {
    RemoveEntry $HostName $IPAddress $Comment
}

WriteHostsFile $hosts
$true
