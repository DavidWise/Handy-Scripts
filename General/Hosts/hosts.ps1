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

.PARAMETER Version
Forces the script to display the version information

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

    [Alias("raw")]
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
    [Parameter(ParameterSetName=’listHosts’)]
    [Alias("tag")]
    [string] $Tags,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $TagOpen,

    [Parameter(ParameterSetName=’addHosts’)]
    [Parameter(ParameterSetName=’removeHosts’)]
    [string] $TagClose,

    [Parameter(ParameterSetName=’removeHosts’)]
    [Parameter(ParameterSetName=’listHosts’)]
    [ValidateSet("Exact", "Any", "All", "Blend")]
    [string] $TagMatchMode = "Blend",

    [Alias("v","ver")]
    [switch] $version
)

$hostsLib = Join-Path (Split-Path -Parent $PSCommandPath) "hosts.lib.ps1"
. "$hostsLib"

# the functions here need to interact with the switches passed
function IsListOnly() {
    $psetName = $PSCmdlet.ParameterSetName

    ($list.IsPresent -or ($psetName -eq "listHosts" -and $list.IsPresent -eq $false))
}

function GetInputFilePath() {
    # Placeholder - eventually allow this to be specified via parameter
    "$($env:windir)\System32\drivers\etc\hosts"
}

function GetOutputFilePath() {
    # Placeholder - eventually allow this to be specified via parameter
    GetInputFilePath
}

$listHosts  = IsListOnly
$sourceFile = GetInputFilePath
$destinationFile = GetOutputFilePath


DisplaySpash $version.IsPresent


if ($full.IsPresent) {
    Get-Content $sourceFile | Write-Output
    return
}

SetTagPrefix $TagOpen
SetTagSuffix $TagClose
SetTagCompareMode $TagMatchMode

$TagValues = ParseTag $Tags

$hostEntries = ParseHostsFile $sourceFile

if ($listHosts -eq $true) { 
    ListEntries $hostEntries $TagValues
    exit 0
}


function TryElevatedTasks($originalEntries, $newTags) {
    $isAdmin = IsAdministrator

    $revisedEntries = $originalEntries


    if (($add.IsPresent -or $remove.IsPresent) -and $isAdmin -eq $false) {
        ExitWithMessage 2 -ForegroundColor Yellow "Script must be run as Administrator in order to make any changes" 
    }

    if ($add.IsPresent) {
        $revisedEntries = AddEntry $revisedEntries $HostName $IPAddress $ReplaceIfExists.IsPresent $Comment $BlockDomain.IsPresent $newTags
    }

    if ($remove.IsPresent) {
        $revisedEntries = RemoveEntry $revisedEntries $HostName $IPAddress $Comment $newTags
    }

    WriteHostsFile $revisedEntries $destinationFile
}

TryElevatedTasks $hostEntries $TagValues