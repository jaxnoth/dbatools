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

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER DataDomainBoostHost
        Specifies the name of the Data Domain or PowerProtect X400 server that contains the storage unit where you want to back up the databases.

    .PARAMETER DataDomainBoostDevicePath
        Specifies the name and the path of the storage unit where you want to direct the backup.

    .PARAMETER DataDomainBoostUser
        Specifies the username of the DD Boost user.

        You must register the hostname and the DD Boost username in the lockbox to enable Microsoft application agent to retrieve the password for the registered user.

    .PARAMETER DataDomainBoostLockboxPath
        Specifies the server or UNC path to the lockbox

    .PARAMETER DataDomainAgentPath
        Optional parameter to override the registry or default installation path of the Agent

    .PARAMETER CleanupTime
        Number of days before the backup expires.

    .PARAMETER Type
        Backup type of Full, Diff, or Incr

        Defaults to Full

    .PARAMETER Checksum
        If this switch is enabled, the backup checksum will be calculated.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string] $DataDomainBoostHost,
        [string] $DataDomainBoostDevicePath,
        [string] $DataDomainBoostUser,
        [string] $DataDomainBoostLockboxPath,
        [string] $DataDomainAgentPath,
        [string] $CleanupTime = 14,
        [ValidateSet('Full', 'Diff', 'Incr')]
        [string] $Type = 'Full',
        [switch] $Checksum = $False
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

            if ($ExcludeDatabase) {
                $InputObject = $InputObject | Where-Object Name -notin $ExcludeDatabase
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

        If ($Checksum) {
            $Args += @('-k')
        }

        switch ($Type) {
            "Incr" { $Args += @("-a `"SKIP_SIMPLE_DATABASES=TRUE`"") }
        }

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
        $fileExe = Get-DbaDDBoostAgentLocation -ComputerName $SqlInstance.ComputerName -Credential $SqlCredential -DataDomainAgentPath $DataDomainAgentPath
        $fileExe = Join-SomePath $fileExe "bin\ddbmsqlsv.exe"

        if ($PSCmdlet.ShouldProcess("$SqlInstance", "Backup Databases $($Database -join ', ')")) {
            try {
                $programResult = Invoke-Program -ComputerName $SqlInstance -Path $fileExe -Authentication CredSSP -Credential $SqlCredential -ArgumentList $Args -EnableException $True
                Write-Message -Message "Program Output: $($programResult.stdout)" -Level Verbose
                if (-not $programResult.Successful) {
                    $msg = "Program failed with exit code $($programResult.ExitCode)"
                    Stop-Function -Message $msg
                }
            } catch {
                Write-Message -Message "Program Output: $($programResult.stdout)" -Level Verbose
                Write-Message -Message "Program Error: $($programResult.stderr)" -Level Warning
            }

        }
    }
}