function Backup-DbaDDBoostDatabase {
    <#
    .SYNOPSIS
        Backup one or more SQL Sever databases from a single SQL Server SqlInstance.

    .DESCRIPTION
        Performs a backup of a specified type of 1 or more databases on a single SQL Server Instance. These backups may be Full, Differential or Transaction log backups.

    .PARAMETER SqlInstance
        The SQL Server instance hosting the databases to be backed up.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER DataDomainBoostHost
        Data Domain Server
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [string] $DataDomainBoostHost,
        [string] $DataDomainBoostDevicePath,
        [string] $DataDomainBoostUser,
        [string] $DataDomainBoostLockboxPath,
        [string] $DataDomainAgentPath,
        [string] $CleanupTime = 14,
        [ValidateSet('Full', 'Diff', 'Incr')]
        [string]$Type = 'Full'
    )

    BEGIN {

        if ($SqlInstance) {
            try {
                $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Cannot connect to $SqlInstance" -ErrorRecord $_ -EnableException $true
                return
            }

            $InputObject = $server.Databases | Where-Object Name -ne 'tempdb'

            if ($Database) {
                $InputObject = $InputObject | Where-Object Name -in $Database
            }

            if ($DataDomainBoostLockboxPath -eq '' -or ($True -ne (Test-Path $DataDomainBoostLockboxPath -PathType Container))) {
                Stop-Function -Message "Path ($DataDomainBoostLockboxPath)to DDBoost Lockbox is invalid" -EnableException $true
            }

            if ($CleanupTime) {
                $Retention = $CleanupTime + 'd'
            }
        }

        $FQDN = (Resolve-DbaNetworkName -ComputerName $SqlInstance.ComputerName).FQDN


        Write-Verbose "Creating backup string"
        $Args = @(
            "-c $($FQDN)",
            "-l $Type",
            "-y +$Retention",
            "-a `"NSR_DFA_SI_DD_HOST=$DataDomainBoostHost`"",
            "-a `"NSR_DFA_SI_DD_USER=$DataDomainBoostUser`"",
            "-a `"NSR_DFA_SI_DEVICE_PATH=$DataDomainBoostDevicePath`"",
            "-a `"NSR_DFA_SI_DD_LOCKBOX_PATH=$DataDomainBoostLockboxPath`"",
            "-a `"NSR_SKIP_NON_BACKUPABLE_STATE_DB=TRUE`""
        )

        # Retrieves currently running agent on machine to determine required options
        $Agent = Get-CimInstance -ComputerName $SqlInstance.ComputerName -ClassName Win32_Product -Filter "Caption Like 'Microsoft Application Agent'"
        $AgentVersion = $Agent.Version[0] + $Agent.Version[2]
        If (-not $AgentVersion) {
            $Args += @(
                "-a NSR_DFA_SI=TRUE",
                "-a NSR_DFA_SI_USE_DD=TRUE"
            )
        }

        foreach ($I IN $InputObject) {
            switch ($SqlInstance.InstanceName) {
                "MSSQLSERVER" { $Args += @("MSSQL:$($I.Name)") }
                Default { $Args += @('MSSQL$' + $SqlInstance.InstanceName + ":$($I.Name)") }
            }
        }
    }
    end {
        If ($DataDomainAgentPath) {
            $fileExe = $DataDomainAgentPath
        } else {
            $Node = Invoke-Command2 -ComputerName $SqlInstance -Credential $SqlCredential -ScriptBlock {
                $Node = Get-ItemProperty HKLM:\SOFTWARE\WOW6432Node\EMC\DDBMSS
                If (-Not $Node) {
                    $Node = Get-ItemProperty HKLM:\SOFTWARE\EMC\DDBMSS
                }
                return $Node
            }
            If (-Not $Node) {
                $fileExe = 'C:\Program Files\DPSAPPS\MSAPPAGENT\'
            } else {
                $fileExe = $Node.Path
            }
        }
        $fileExe = [IO.Path]::Combine([string[]]@($fileExe, "bin\ddbmsqlsv.exe"))
        $ExecutableString = "cmd /c '`"$fileExe`" $($Args -join ' ')'"
        # Write-Verbose "Executing: $scriptblock"
        if ($PSCmdlet.ShouldProcess("$SqlInstance", "Backup Databases $($Database -join ', ')")) {
            Write-Message -Message $ExecutableString -Level Verbose
            try {
                $backupResult = Invoke-Program -ComputerName $SqlInstance -Path $fileExe -Authentication CredSSP -Credential $SqlCredential -ArgumentList $Args -EnableException $True
                if (-not $backupResult.Successful) {
                    $msg = "Backup failed with exit code $($backupResult.ExitCode)"
                    Stop-Function -Message $msg
                }
            } catch {
                Write-Error -Message $backupResult.stdout
            }

        }
    }
}