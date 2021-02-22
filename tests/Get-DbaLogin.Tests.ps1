$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'IncludeFilter', 'ExcludeLogin', 'ExcludeFilter', 'ExcludeSystemLogin', 'Type', 'HasAccess', 'Locked', 'Disabled', , 'MustChangePassword', 'Detailed', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random

        $password = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
        New-DbaLogin -SqlInstance $script:instance1 -Login "testlogin1_$random" -Password $password
        New-DbaLogin -SqlInstance $script:instance1 -Login "testlogin2_$random" -Password $password
    }

    AfterAll {
        Remove-DbaLogin -SqlInstance $script:instance1 -Login "testlogin1_$random", "testlogin2_$random" -Confirm:$false -Force
    }

    Context "Does sql instance have a SA account" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
        It "Should report that one account named SA exists" {
            $results.Count | Should Be 1
        }
    }

    Context "Check that SA account is enabled" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
        It "Should say the SA account is disabled FALSE" {
            $results.IsDisabled | Should Be "False"
        }
    }

    Context "Check that SA account is SQL Login" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa -Type SQL -Detailed
        It "Should report that one SQL Login named SA exists" {
            $results.Count | Should Be 1
        }
        It "Should get LoginProperties via Detailed switch" {
            $results.BadPasswordCount | Should Not Be $null
            $results.PasswordHash | Should Not Be $null
        }
    }

    Context "Validate params" {

        It "Multiple logins" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -Login "testlogin1_$random", "testlogin2_$random" -Type SQL
            $results.Count | Should -Be 2
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeLogin" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -ExcludeLogin "testlogin2_$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin2_$random"
            $results.Name | Should -Contain "testlogin1_$random"

            $results = Get-DbaLogin -SqlInstance $script:instance1 -ExcludeLogin "testlogin1_$random", "testlogin2_$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin2_$random"
            $results.Name | Should -Not -Contain "testlogin1_$random"
        }

        It "IncludeFilter" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -IncludeFilter "*$random" -Type SQL
            $results.Count | Should -Be 2
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeFilter" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -ExcludeFilter "*$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin1_$random"
            $results.Name | Should -Not -Contain "testlogin2_$random"
        }

        It "ExcludeSystemLogin" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -ExcludeSystemLogin -Type SQL
            $results.Name | Should -Not -Contain "sa"
        }

        It "HasAccess" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -HasAccess -Type SQL
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "Disabled" {
            $null = Set-DbaLogin -SqlInstance $script:instance1 -Login "testlogin1_$random" -Disable
            $result = Get-DbaLogin -SqlInstance $script:instance1 -Disabled
            $result.Name | Should -Contain "testlogin1_$random"
            $null = Set-DbaLogin -SqlInstance $script:instance1 -Login "testlogin1_$random" -Enable
        }

        It "Detailed" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -Detailed -Type SQL

            $results.Count | Should -BeGreaterOrEqual 2

            ($results[0].PSobject.Properties.Name -contains "BadPasswordCount") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "BadPasswordTime") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "DaysUntilExpiration") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "HistoryLength") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "IsMustChange") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "LockoutTime") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "PasswordHash") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "PasswordLastSetTime") | Should -Be $true
        }
    }
}