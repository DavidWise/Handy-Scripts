$tagTokenPrefix = " #["
$tagTokenSuffix = "]"
$changesMade = $false


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

function SetTagPrefix([string] $value) {
    if (-not [string]::IsNullOrWhiteSpace($value)) { $script:tagTokenPrefix = $value }
}

function SetTagSuffix([string] $value) {
    if (-not [string]::IsNullOrWhiteSpace($value)) { $script:tagTokenSuffix = $value }
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


function GetTagCompareMode([string] $newMode, [string] $defaultMode) {
    $validCompareModes = @("Exact", "Any", "All", "Blend")
    $result = $defaultMode
    if ([string]::IsNullOrWhiteSpace($result)) { $result = $TagMatchMode }
    

    if (-not [string]::IsNullOrWhiteSpace($newMode)) { $result = $newMode }


    if ([string]::IsNullOrWhiteSpace($result)) { $result = "Blend" }

    $resultMode = $validCompareModes | % {
        if ($_ -eq $result) { $_ }
    }

    if ($resultMode -eq $null) {
        throw "Unexpected tag compare mode of '$resultMode'"
    }

    
    $resultMode
}


function ParseTag([string] $value) {
    $result = $null

    if ([string]::IsNullOrWhiteSpace($value) -eq $false) {
        $inTags = $value.Split(@(',', ' ','#', ';'), [System.StringSplitOptions]::RemoveEmptyEntries)

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
    $hostfile = Get-Content $hostsPath
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



function ListEntries($originalEntries, $requestedTags, $matchMode) {
    $matched = $originalEntries | where {$_.IsEntry} 
    if ($requestedTags -ne $null) { 
        $tagCompareMode = GetTagCompareMode $matchMode
        $matched = $matched | where {(MatchesTags $tagCompareMode ($_.TagValues) $requestedTags) -eq $true} 
    }
    $matched | select Host, Address, Comment, Tags | sort Host
}


function AddEntry($originalEntries, [string]$newHost, [string] $newIP, [bool] $replace, [string] $addComment, [bool] $block, $newTags) {
    $result = @()
    if ($originalEntries -ne $null) { $result = $originalEntries }

    $targetIP = "$newIP".Trim()
    $targetHost = "$newHost".Trim()
    if ([string]::IsNullOrWhiteSpace($targetIP)) { $targetIP = "127.0.0.1" }
    if ($block) { $targetIP = "0.0.0.0" }

    if ([string]::IsNullOrWhiteSpace($targetHost)) { 
        ExitWithMessage 1 -foreColor Red "a host name is required"
    }

    $addEntry = $result | where { $_.host -eq $targetHost }

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
    $addEntry.TagValues = AddToTags $addEntry.TagValues $newTags

    $Script:changesMade = $true
    $result
}


function MatchesValue([string] $value1, [string] $value2) {
    $val1 = "$value1".Trim()
    $val2 = "$value2".Trim()

    # both items must have a value in order to be evaluated
    if ([string]::IsNullOrEmpty($val1) -or [string]::IsNullOrEmpty($val2)) { return $false }

    return ($val1 -eq $val2)
}


function RemoveEntry($originalEntries, [string]$oldHost, [string] $oldIP, [string] $oldComment, $findTagValues) {
    $result = $originalEntries | % {
        $isamatch = (MatchesValue $oldHost $_.Host) -or (MatchesValue $oldIP $_.Address) -or (MatchesValue $oldComment $_.Comment)

        # look at tags if we need to
        if (-not $isamatch -and -not (IsEmpty $findTagValues)) {
            $tagMatches = MatchesTags $TagMatchMode $_.TagValues $findTagValues

            if ($tagMatches) {
                if ($TagMatchMode -ne "Blend") { $isamatch = $true }
                else {
                    $_.TagValues = StripMatchingTags $_.TagValues $findTagValues

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
    $result
}


function WriteHostsFile($originalEntries, [string] $hostsPath) {
    if ($changesMade -eq $false) { return }

    $outEntries = $originalEntries | where {$_.Deleted -ne $true }

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


function DisplaySpash() {
    if ($version.IsPresent -eq $false -and $env:HostsSplashDisplayed -eq "Y") { return }
    $verFile = Join-Path $PSScriptRoot "version"
    $ver = ""
    if ((Test-Path $verFile) -eq $true) { $ver = "v$((get-content $verFile).Trim())" }

    write-host 
    write-host "HandyScripts - .\Hosts.ps1" -ForegroundColor Cyan -NoNewline
    write-host "  $ver" -ForegroundColor Green -NoNewline
    write-host "  -- David J. Wise -- " -ForegroundColor Cyan -NoNewline
    write-host "https://github.com/DavidWise/Handy-Scripts" -ForegroundColor Yellow
    $env:HostsSplashDisplayed = "Y"
}