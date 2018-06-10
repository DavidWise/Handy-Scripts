﻿<#
.SYNOPSIS 
Performs basic operations related to managing the local 'hosts' file (List, Add, Remove).  By default, the hosts file is located in %WINDIR%/System32/drivers/etc and has no extension

.DESCRIPTION
Allows the caller to easily manipulate the local hosts file either directly or via scripts or batch commands.  

The local hosts is (usually) the first place the machine looks to determine where a host is located.  Adding entries here allows redirecting of otherwise public URLs to
instead go to desired target machines, usually localhost (aka 127.0.0.1)

This is intended to help web developers with API routing and such. Dont be evil


.PARAMETER list
if present, it will list the mappings defined in the hosts file.  This is the default action if no arguments are included

.PARAMETER full
Writes out the entirety of the local hosts file

.PARAMETER add
Initiates the adding of an entry to the local hosts file.  If no -IPAddress is specified, it will assumoe 127.0.0.1 (localhost)
If the entry exists, it will not be overwritten unless -ReplaceIfExists is also specified

.PARAMETER remove
Removes an item from the hosts file.  Requires that -HostName, -IPAddress or -Comment be specified and will match on what is passed on the included parameter
No error is thrown if the desired item is not found

.PARAMETER HostName
The DNS host name to be included in the action. This is the default first parameter for -Add and -Remove

.PARAMETER IPAddress
The IP address to route the associated HostName to

.PARAMETER Comment
Any comment associated with the IP address, i.e. "Added by RobertsDP for the Iocane project"

.PARAMETER ReplaceIfExists
Used in associate with -Add to force the item to be written even if it already exists

#>
[CmdletBinding(
    DefaultParameterSetName="listHosts",
    SupportsShouldProcess = $False,
    SupportsPaging = $False

)]
param (
    [Parameter(ParameterSetName=’listHosts’)]
    [switch] $list,

    [Parameter(ParameterSetName=’showHosts’)]
    [switch] $full,

    [Parameter(ParameterSetName=’addHosts’, Mandatory=$true)]
    [switch] $add,

    [Parameter(ParameterSetName=’removeHosts’, Mandatory=$true)]
    [switch] $remove,

    [Parameter(ParameterSetName=’addHosts’, Position=0)]
    [string] $HostName,

    [Parameter(ParameterSetName=’addHosts’, Position=1)]
    [string] $IPAddress,

    [Parameter(ParameterSetName=’addHosts’)]
    [switch] $ReplaceIfExists,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $Comment
)

$psetName = $PSCmdlet.ParameterSetName

$listHosts = ($list.IsPresent -or ($psetName -eq "listHosts" -and $list.IsPresent -eq $false))

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
    if ($listHosts -eq $false) { return }
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
    return
}

$entries = GetHostsFile $hosts

if ($listHosts -eq $true) { 
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