<#
.SYNOPSIS 
Performs basic operations related to managing the local 'hosts' file (List, Add, Remove).  By default, the hosts file is located in %WINDIR%/System32/drivers/etc and has no extension

.DESCRIPTION
Allows the caller to easily manipulate the local hosts file either directly or via scripts or batch commands.  

The local hosts is (usually) the first place the machine looks to determine where a host is located.  Adding entries here allows redirecting of otherwise public URLs to
instead go to desired target machines, usually localhost (aka 127.0.0.1)

This is intended to help web developers with API routing and such. Dont be evil

The latest version of this file is available at: https://github.com/DavidWise/Handy-Scripts/tree/master/General/Hosts


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

.PARAMETER BlockDomain
The domain will be added to the hosts file with an IP address of 0.0.0.0, effectively blocking all requests to that domain

.PARAMETER Comment
Any comment associated with the IP address, i.e. "Added by RobertsDP for the Iocane project"

.PARAMETER Tags
A comma-delimted list of tags to associate the entry with on -Add or to match against on -Remove.  
For -Add, the entry is added with the tags specified.  If the entry already exists, any new tags are also added to the entry
for -Remove, all tags specified must be on the item in order to match.  For Example, if the item include the tags RED,BLUE,WHITE and the -Remove specifies RED,GREEN the item would not be a match since the original tag list does not include both RED and GREEN

.PARAMETER TagOpen
Specifies the text indicator that identifies the start of a tag block in the comment.  Default is " #["
using custom TagOpen and TagClose allows callers to specify unique tag blocks - use with caution

.PARAMETER TagClose
Specifies the text indicator that identifies the end of a tag block in the comment.  Default is "]"
using custom TagOpen and TagClose allows callers to specify unique tag blocks - use with caution

.PARAMETER ReplaceIfExists
Used in associate with -Add to force the item to be written even if it already exists

.PARAMETER TagMatchMode
Determines the matching algorithm used when evaluating tags for removal
- All - All tags passed in on the Remove Request must be present 
- Any - Any of the tags passed in on the Remove Request must be present 
- Exact - All the tags passed in must be the only tags defined on an item 
- Blend - Behaves like -All- except that it only removes matched tags from the item.  If all tags are removed then the item is removed. 
Blend is the default since it matches the default behavior of -Add and allows multiple tags to share the same host entry

.NOTES
Future Enhancements
- Bulk import of actions via CSV or Pipeline
- incorporate Tags into the -List logic

TBD
- Need more unit tests around reading and writing of the host file as well as verifying the changes

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
    [Parameter(ParameterSetName=’removeHosts’, Position=0)]
    [string] $HostName,

    [Parameter(ParameterSetName=’addHosts’, Position=1)]
    [string] $IPAddress,

    [Parameter(ParameterSetName=’addHosts’)]
    [switch] $ReplaceIfExists,

    [Parameter(ParameterSetName=’addHosts’)]
    [switch] $BlockDomain,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $Comment,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $Tags,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $TagOpen,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $TagClose,

    [Parameter(ParameterSetName=’removeHosts’)]
    [ValidateSet("Exact", "Any", "All", "Blend")]
    
    [string] $TagMatchMode = "Blend"
)

$psetName = $PSCmdlet.ParameterSetName

$listHosts = ($list.IsPresent -or ($psetName -eq "listHosts" -and $list.IsPresent -eq $false))

$hosts = "$($env:windir)\System32\drivers\etc\hosts"
$changesMade = $false
$entries = @()

$TagValues = $null

$tagTokenPrefix = " #["
$tagTokenSuffix = "]"

if([string]::IsNullOrWhiteSpace($TagOpen) -eq $false) {$tagTokenPrefix = $TagOpen }
if([string]::IsNullOrWhiteSpace($TagClose) -eq $false) {$tagTokenSuffix = $TagClose }


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
    $obj | Add-Member -MemberType NoteProperty -Name "TagValues" -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name "Tags" -Value ""
    
    $obj
}


function ParseTag([string] $value) {
    $result = $null

    if ([string]::IsNullOrWhiteSpace($value) -eq $false) {
        $inTags = $value.Split(@(',', ' ','#'), [System.StringSplitOptions]::RemoveEmptyEntries)

        $result = $inTags | % { $_ }
    }

    $result
}


function GetTagBlock([string] $value) {
    # requires that the tags be in the " #[Tag1,Tag2]" format
    $result = ""

    if ([string]::IsNullOrWhiteSpace($value) -eq $false) {
        $startPos = $value.IndexOf($tagTokenPrefix)

        if ($startPos -ge 0) {
            $chunk = $value.Substring($startPos)

            $endPos = $chunk.IndexOf($tagTokenSuffix)
            if ($endPos -gt 0) { 
                $chunk = $chunk.Substring(0,$endpos+1)
                $result = $chunk
            }
        }
    }

    $result
}


function ParseTagFromComment([string] $value) {
    # requires that the tags be in the " #[Tag1,Tag2]" format
    $result = $null

    $tagBlock = GetTagBlock $value

    if ([string]::IsNullOrWhiteSpace($tagBlock) -eq $false) {
        $chunk = $tagBlock.SubString($tagTokenPrefix.Length)

        $endPos = $chunk.IndexOf($tagTokenSuffix)
        if ($endPos -gt 0) { 
            $chunk = $chunk.Substring(0,$endpos)
            $result = ParseTag $chunk
        }
    }

    $result
}


function RemoveTagFromComment([string] $value) {
    $result = ""
    if ([string]::IsNullOrWhiteSpace($value) -eq $false) {
        $tagBlock = GetTagBlock $value
        if ([string]::IsNullOrWhiteSpace($tagBlock) -eq $false) {
            $result = $value.Replace($tagBlock, "")
        }
    }

    $result
}



function BuildTags([object[]] $values) {
    $result = ""

    if ($values -ne $null -and $values.Length -gt 0) {
        $vals = [string[]] $values
        $result = [string]::Join(",", $vals)
    }
    $result
}


function IsEmpty([object[]] $values) {
    if ($values -eq $null) { return $true }
    if ($values.Length -lt 1) { return $true }
    return $false
}


function AddToTags([object[]] $oldValues, [object[]] $newValues) {
    #simple and most common cases first

    #nothing in either
    if ((IsEmpty $newValues) -and (IsEmpty $oldValues)) { return $null }

    #nothing new to add
    if (IsEmpty $newValues) { return $oldValues }

    # no old data so return just the new
    if (IsEmpty $oldValues) { return $newValues }

    #some merge has to happen
    $result = $oldValues
    if ($result -eq $null) {$result = @()}

    $newValues | % {
        $newVal = [string] $_
        $doAdd = $true

        $result | % { 
            $oldVal = [string] $_
            if ($oldVal -eq $newval) {$doAdd = $false }
        }

        if ($doAdd) { $result += $newVal }
    }

    $result
}


function ParseHostsFile([string] $hostsPath) {
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

            $obj.TagValues = ParseTagFromComment $obj.Comment
            $obj.Tags = BuildTags $obj.TagValues

            $obj.Comment = RemoveTagFromComment $obj.Comment
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



function MatchesTags([string]$matchMode, [object[]] $currentTags, [object[]] $compareTags) {
    #if both are empty, its a match regardless of the mode
    if ((IsEmpty $currentTags) -and (IsEmpty $compareTags)) { return $true }

    # if there are no current tags then obviously none of the new ones will match
    if ((IsEmpty $currentTags) -and (-not (IsEmpty $compareTags))) { return $false }

    # if there are current tags but no new ones then it doesnt match
    if ((-not (IsEmpty $currentTags)) -and (IsEmpty $compareTags)) { return $false }

    $matchCount = 0
    #loop through
    $compareTags | % {
        $newTag = [string] $_

        $currentTags | % {
            $oldTag = [string] $_

            if ($oldTag -eq $newTag) { $matchCount++ }
        }
    }

    if ($matchMode -eq "All" -and $matchCount -eq $compareTags.Length) { return $true }
    if ($matchMode -eq "Any" -and $matchCount -gt 0) { return $true }
    if ($matchMode -eq "Exact" -and $matchCount -eq $compareTags.Length -and $matchCount -eq $currentTags.Length) { return $true }
    if ($matchMode -eq "Blend" -and $matchCount -eq $compareTags.Length) { return $true }

    $false
}



function StripMatchingTags([object[]] $currentTags, [object[]] $compareTags) {
    if (IsEmpty $currentTags -and IsEmpty $compareTags) { return $null }
    if (IsEmpty $currentTags) { return $null }
    if (IsEmpty $compareTags) { return $currentTags }

    $newTags = @()
    $currentTags | % {
        $oldTag = [string] $_
        $matches = $false

        $compareTags | % {
            $newTag = [string] $_
            if ($oldTag -eq $newTag) {$matches = $true}
        }

        if (-not $matches) { $newTags += $oldTag }
    }

    $newTags
}



function ListEntries($entries) {
    if ($listHosts -eq $false) { return }
    $entries | where {$_.IsEntry} | select Host, Address, Comment, Tags | sort Host
}


function AddEntry([string]$newHost, [string] $newIP, [bool] $replace, [string] $addComment, [bool] $block) {
    $targetIP = "$newIP".Trim()
    $targetHost = "$newHost".Trim()
    if ([string]::IsNullOrWhiteSpace($targetIP)) { $targetIP = "127.0.0.1" }
    if ($block) { $targetIP = "0.0.0.0" }

    if ([string]::IsNullOrWhiteSpace($targetHost)) { 
        ExitWithMessage 1 -foreColor Red "a host name is required"
    }

    $addEntry = $entries | where { $_.host -eq $targetHost }

    if ($addEntry -ne $null -and $replace -eq $false) {
        ExitWithMessage 3 -ForegroundColor Red  "An entry for that host already exists.  Use the -ReplaceIfExists switch to force it to replace"
    }

    if ($addEntry -eq $null) {
        $addEntry = newEntry
        $script:entries += $addEntry
    }

    if ([string]::IsNullOrWhiteSpace($addComment) -eq $false) {
        $addEntry.Comment = $addComment
    }

    $addEntry.Host = $targetHost
    $addEntry.Address = $targetIP
    $addEntry.Added = $true
    $addEntry.IsEntry = $true
    $addEntry.TagValues = AddToTags $addEntry.TagValues $TagValues

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

        # look at tags if we need to
        if (-not $isamatch -and -not (IsEmpty $TagValues)) {
            $tagMatches = MatchesTags $TagMatchMode $_.TagValues $TagValues

            if ($tagMatches) {
                if ($TagMatchMode -ne "Blend") { $isamatch = $true }
                else {
                    $_.TagValues = StripMatchingTags $_.TagValues $TagValues

                    if (-not (IsEmpty $_.TagValues)) { $Script:changesMade = $true }
                    else {
                        $isamatch = $true 
                    }
                }
            }
        }

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
        $outTag = ""
        $outComment = ""
        if ([string]::IsNullOrWhiteSpace($_.Comment) -eq $false) { $outComment = "#" + $_.Comment }

        $tagVals = BuildTags $_.TagValues
        if (-not [string]::IsNullOrWhiteSpace($tagVals)) {
            $outTag = "$($tagTokenPrefix)$($tagVals)$($tagTokenSuffix)"
            # if only a tag was listed, make sure there is a comment indicator first
            if ($outComment -eq "") { $outComment = "# " }
        }

        if ($_.IsEntry -eq $true) {
            $_.OutputValue = [string]::Format("{0, -" + $maxIPLen.ToString() + "} {1, -" + $maxHostLen.ToString() + "} {2}{3}", $_.Address, $_.Host, $outComment, $outTag).trim()
        }
    }


    $newEntries = $outEntries | % { $_.OutputValue }

    $info = New-Object System.IO.FileInfo($hostsPath)

    $backupFileName = [string]::Format("hosts_bk_{0:yyyyMMddHHmmss}", [DateTime]::Now)

    $bakfile = [System.IO.Path]::Combine($info.DirectoryName, $backupFileName)

    $copied = [System.IO.File]::Copy($hostsPath, $bakfile)

    $newEntries | Out-File $hostsPath -Encoding ascii 

    Write-Host "Changes written successfully" -ForegroundColor Green
}


if ($full.IsPresent) {
    Get-Content $hosts | Write-Output
    return
}

$TagValues = ParseTag $Tags

$entries = ParseHostsFile $hosts

if ($listHosts -eq $true) { 
    ListEntries $entries 
    return
}


$isAdmin = IsAdministrator


if (($add.IsPresent -or $remove.IsPresent) -and $isAdmin -eq $false) {
    ExitWithMessage 2 -ForegroundColor Yellow "Script must be run as Administrator in order to make any changes" 
}

if ($add.IsPresent) {
    AddEntry $HostName $IPAddress $ReplaceIfExists.IsPresent $Comment $BlockDomain.IsPresent
}

if ($remove.IsPresent) {
    RemoveEntry $HostName $IPAddress $Comment
}

WriteHostsFile $hosts