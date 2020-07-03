#using Pester for testing - https://github.com/pester/Pester


$testCmd = get-item $PSCommandPath
$here = $testCmd.DirectoryName
$sut = $testCmd.Name -replace '\.Tests\.', '.'
$fullPath = Join-Path $here $sut
. "$fullPath"

$Global:testDataFolder = Join-Path $here "Tests"
$TestTagBlock = "$($hostLibSettings.TagTokenPrefix)Tag1,Tag2,Tag3$($hostLibSettings.TagTokenSuffix)"
$ExpectedTagBlock = @("Tag1", "Tag2", "Tag3")


function GetHostEntryTestData([string] $testDataFileName) {
    $hostsData = join-path $testDataFolder $testDataFileName
    if ((Test-Path $hostsData) -eq $true) {
        return ParseHostsFile $hostsData
    }
}

$Global:testDataHostsBase = GetHostEntryTestData "Hosts.Base"

Context 'GetTagBlock' {
    It "Given <Given> returns <Expected>" -TestCases @(
        @{Given = $null; Expected = ""}
        @{Given = ""; Expected = ""}
        @{Given = "  `t"; Expected = ""}
        @{Given = "Some Value with no tags"; Expected = ""}
        @{Given = $TestTagBlock; Expected = $TestTagBlock}
        @{Given = "Ends with $TestTagBlock"; Expected = $TestTagBlock}
        @{Given = "$TestTagBlock at the start"; Expected = $TestTagBlock}
        @{Given = "Has a $TestTagBlock In the middle"; Expected = $TestTagBlock}
        @{Given = "Has a $($hostLibSettings.tagTokenPrefix) In the middle but no end"; Expected = ""}
        
    ) {
        param($Given, $Expected)

        $val = GetTagBlock $Given
        $val | should -be $Expected
    }
}


Context 'ParseTag' {
    It "Given <Given> returns <Expected>" -TestCases @(
        @{Given = $null; Expected = $null}
        @{Given = ""; Expected = $null}
        @{Given = "  `t"; Expected = $null}
        @{Given = "Tag1"; Expected = "Tag1"}
        @{Given = "Tag1,Tag2"; Expected = @("Tag1", "Tag2")}
        @{Given = "Tag1,Tag2,Alpha"; Expected = @("Tag1", "Tag2", "Alpha")}
        @{Given = "Tag1, Tag2"; Expected = @("Tag1", "Tag2")}
        @{Given = "#Tag1 #Tag2"; Expected = @("Tag1", "Tag2")}
        @{Given = "#Tag1, #Tag2"; Expected = @("Tag1", "Tag2")}
    ) {
        param($Given, $Expected)

        $val = ParseTag $Given
        $val | should -be $Expected
    }
}

Context 'ParseTagFromComment' {
    It "Given <Given> returns <Expected>" -TestCases @(
        @{Given = $null; Expected = $null}
        @{Given = ""; Expected = $null}
        @{Given = "  `t"; Expected = $null}
        @{Given = $TestTagBlock; Expected = $ExpectedTagBlock}
        @{Given = "# Some text $TestTagBlock"; Expected = $ExpectedTagBlock}
        @{Given = "$TestTagBlock after"; Expected = $ExpectedTagBlock}
        @{Given = "#in the $TestTagBlock middle"; Expected = $ExpectedTagBlock}
    ) {
        param($Given, $Expected)

        $val = ParseTagFromComment $Given
        $val | should -be $Expected
    }
}


Context 'RemoveTagFromComment' {
    It "Given <Given> returns <Expected>" -TestCases @(
        @{Given = $null; Expected = ""}
        @{Given = ""; Expected = ""}
        @{Given = "  `t"; Expected = ""}
        @{Given = $TestTagBlock; Expected = ""}
        @{Given = "# Some text $TestTagBlock"; Expected = "# Some text "}
        @{Given = "$TestTagBlock after"; Expected = " after"}
        @{Given = "#in the $TestTagBlock middle"; Expected = "#in the  middle"}
    ) {
        param($Given, $Expected)

        $val = RemoveTagFromComment $Given
        $val | should -be $Expected
    }
}

Context 'BuildTags' {
    It "Given <Given> returns <Expected>" -TestCases @(
        @{Given = $null; Expected = ""}
        @{Given = ""; Expected = ""}
        @{Given = @(); Expected = ""}
        @{Given = @("Tag1"); Expected = "Tag1"}
        @{Given = @("Tag1","Tag2"); Expected = "Tag1,Tag2"}
    ) {
        param($Given, $Expected)

        $val = BuildTags $Given
        $val | should -be $Expected
    }
}

Context 'AddToTags' {
    It "Given <OldValues> and adding <NewValues> returns <Expected>" -TestCases @(
        @{OldValues = $null; NewValues = $null;  Expected = $null}
        @{OldValues = $null; NewValues = @();  Expected = $null}
        @{OldValues = @(); NewValues = @();  Expected = $null}
        @{OldValues = @("Tag1"); NewValues = @();  Expected = @("Tag1")}
        @{OldValues = @("Tag1"); NewValues = @("Tag1");  Expected = @("Tag1")}
        @{OldValues = @("Tag1"); NewValues = @("Tag2");  Expected = @("Tag1", "Tag2")}
    ) {
        param($OldValues, $NewValues, $Expected)

        $val = AddToTags $OldValues $NewValues
        $val | should -be $Expected
    }
}

Context 'MatchesTags' {
    It "Given <Mode> comparing <OldValues> to <NewValues> returns <Expected>" -TestCases @(
        @{Mode="Any"; OldValues = $null; NewValues = $null;  Expected = $true}
        @{Mode="All"; OldValues = $null; NewValues = $null;  Expected = $true}
        @{Mode="Exact"; OldValues = $null; NewValues = $null;  Expected = $true}
        @{Mode="Blend"; OldValues = $null; NewValues = $null;  Expected = $true}

        @{Mode="Any"; OldValues = @(); NewValues = $null;  Expected = $true}
        @{Mode="All"; OldValues = @(); NewValues = $null;  Expected = $true}
        @{Mode="Exact"; OldValues = @(); NewValues = $null;  Expected = $true}
        @{Mode="Blend"; OldValues = @(); NewValues = $null;  Expected = $true}

        @{Mode="Any"; OldValues = @(); NewValues = @();  Expected = $true}
        @{Mode="All"; OldValues = @(); NewValues = @();  Expected = $true}
        @{Mode="Exact"; OldValues = @(); NewValues = @();  Expected = $true}
        @{Mode="Blend"; OldValues = @(); NewValues = @();  Expected = $true}

        @{Mode="Any"; OldValues = @("One"); NewValues = @("One");  Expected = $true}
        @{Mode="Any"; OldValues = @("One"); NewValues = @("Two");  Expected = $false}
        @{Mode="Any"; OldValues = @("One","Two"); NewValues = @("Two");  Expected = $true}
        @{Mode="Any"; OldValues = @("One","Two"); NewValues = @("Nine");  Expected = $false}

        @{Mode="All"; OldValues = @("One"); NewValues = @("One");  Expected = $true}
        @{Mode="All"; OldValues = @("One"); NewValues = @("One", "Two");  Expected = $false}
        @{Mode="All"; OldValues = @("Two", "One"); NewValues = @("One", "Two");  Expected = $true}
        @{Mode="All"; OldValues = @("Two", "One", "Three"); NewValues = @("One", "Two");  Expected = $true}

        @{Mode="Exact"; OldValues = @("One"); NewValues = @("One");  Expected = $true}
        @{Mode="Exact"; OldValues = @("One", "Two"); NewValues = @("One");  Expected = $false}
        @{Mode="Exact"; OldValues = @("One", "Two"); NewValues = @("Two", "One");  Expected = $true}
        @{Mode="Exact"; OldValues = @("One", "Two", "Three"); NewValues = @("Two", "One");  Expected = $false}
        @{Mode="Exact"; OldValues = @("One"); NewValues = @("Two", "One");  Expected = $false}

        @{Mode="Blend"; OldValues = @("One"); NewValues = @("One");  Expected = $true}
        @{Mode="Blend"; OldValues = @("One"); NewValues = @("One", "Two");  Expected = $false}
        @{Mode="Blend"; OldValues = @("Two", "One"); NewValues = @("One", "Two");  Expected = $true}
        @{Mode="Blend"; OldValues = @("Two", "One", "Three"); NewValues = @("One", "Two");  Expected = $true}

    ) {
        param($Mode, $OldValues, $NewValues, $Expected)

        $val = MatchesTags $mode $OldValues $NewValues
        $val | should -be $Expected
    }
}

Context 'StripMatchingTags' {
    It "Given <OldValues> and removing <NewValues> returns <Expected>" -TestCases @(
        @{OldValues = $null; NewValues = $null;  Expected = $null}
        @{OldValues = $null; NewValues = @();  Expected = $null}
        @{OldValues = @(); NewValues = $null;  Expected = $null}
        @{OldValues = @(); NewValues = @();  Expected = $null}
        @{OldValues = @("Tag1"); NewValues = @();  Expected = @("Tag1")}
        @{OldValues = @("Tag1"); NewValues = @("Tag1");  Expected = @()}
        @{OldValues = @("Tag1"); NewValues = @("Tag2");  Expected = @("Tag1")}
        @{OldValues = @("Tag1", "Tag2"); NewValues = @("Tag1", "Tag2");  Expected = @()}
        @{OldValues = @("Tag1", "Tag2", "Tag3"); NewValues = @("Tag1", "Tag2");  Expected = @("Tag3")}
        @{OldValues = @("Tag1", "Tag2"); NewValues = @("Tag1", "Tag2", "Tag3");  Expected = @()}
    ) {
        param($OldValues, $NewValues, $Expected)

        $val = StripMatchingTags $OldValues $NewValues
        $val | should -be $Expected
    }
}


Describe "GetTagCompareMode" {
    Context "Valid Values" {
        It "Given <Given> returns <Expected>" -TestCases @(
            @{Given = "Exact"; Expected = "Exact"}
            @{Given = "Any"; Expected = "Any"}
            @{Given = "All"; Expected = "All"}
            @{Given = "Blend"; Expected = "Blend"}
        ) {
            param($Given, $Expected) 

            $result = GetTagCompareMode $Given
            $result | Should -be $Expected
        }
    }

    Context "default Values" {
        It "Given <Given> returns <Expected>" -TestCases @(
            @{Given = ""; Expected = "Blend"}
            @{Given = " "; Expected = "Blend"}
            @{Given = "`r`n"; Expected = "Blend"}
            @{Given = " `r`n "; Expected = "Blend"}
            @{Given = $null; Expected = "Blend"}
        ) {
            param($Given, $Expected) 

            $result = GetTagCompareMode $Given
            $result | Should -be $Expected
        }
    }

    Context "Bad values throw exception" {
        It "Given <Given> an exception is thrown" -TestCases @(
            @{Given="Junk"}
            @{Given="asdasda s"}
            @{Given="1"}
            @{Given="ALL "}
            @{Given=" ALL"}
            @{Given=" ALL "}
        ) {
            $workedAsExpected = $false
            try {
                $result = GetTagCompareMode $Given
            } catch {
                $workedAsExpected = $true
            }

            $workedAsExpected | Should -BeTrue
        }
    }
}


Describe "ListEntries" {
    Context 'No Tag Filters' {
        It "All Entries shown"  {
            $result = ListEntries $Global:testDataHostsBase

            ($result.length) | Should -be 6
        }
    }

    Context 'Tag default returns expected matches' {
        It "All Entries shown"  {
            $result = ListEntries $Global:testDataHostsBase @("Blue", "Orange") "Any"

            $result | Should -Not -Be $null
            ($result.length) | Should -be 2
        }
    }

}




