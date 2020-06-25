function Remove-DbaDDBoostBackup {
    <#
    .SYNOPSIS
        Removes backups from Data Domain server for a given server.

    .DESCRIPTION
        Removes backups from Data Domain server for a given server.

    .PARAMETER ComputerName
        The SQL Server instance hosting the databases to be backed up.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory)]
        [DbaInstanceParameter]$ComputerName,
        [PSCredential]$Credential,
        # [string] $DataDomainBoostHost,
        # [string] $DataDomainBoostDevicePath,
        # [string] $DataDomainBoostUser,
        [string] $DataDomainBoostLockboxPath
        # [string] $DataDomainAgentPath
    )

    BEGIN {

        # if ($DataDomainBoostLockboxPath -eq '' -or ($True -ne (Test-Path $DataDomainBoostLockboxPath -PathType Container))) {
        #     Stop-Function -Message "Path ($DataDomainBoostLockboxPath)to DDBoost Lockbox is invalid" -EnableException $true
        # }

        #     $Args = @("-k",
        #     "-z `"$Lockbox`"",
        #     "-n mssql",
        #     "-Y"
        # )
        # $ExecutableString = "cmd /c '`"$fileExe`" $($Args -join ' ')'"

        # $fqdn = (Resolve-DbaNetworkName -ComputerName $ComputerName).FQDN

        $Args = @(
            "-k", #Expired Backups
            "-n mssql",
            # "-a `"DEVICE_HOST=$DataDomainBoostHost`"",
            # "-a `"DDBOOST_USER=$DataDomainBoostUser`"",
            # "-a `"DEVICE_PATH=$DataDomainBoostDevicePath`"",
            # "-a `"CLIENT=$fqdn`"",
            # "-a `"NSR_DFA_SI_DD_LOCKBOX_PATH=$DataDomainBoostLockboxPath`"",
            # "-a"
            "-z `"$Lockbox`"",
            "-Y"
        )

    }
    end {
        $agentPath = Get-DbaDDBoostAgentLocation -ComputerName $ComputerName -Credential $Credential -DataDomainAgentPath $DataDomainAgentPath
        # $fileExe = "ddbmexptool.exe"
        $fileExe = Join-SomePath $agentPath "bin\ddbmexptool.exe"
        Write-Message -Message "Calling $fileexe" + [system.String]::Join(" ", $Args) -Level Verbose

        if ($PSCmdlet.ShouldProcess("$ComputerName", "Cleanup backup history")) {
            try {
                $programResult = Invoke-Program -ComputerName $ComputerName -WorkingDirectory $agentPath -Path $fileExe -Authentication CredSSP -Credential $Credential -ArgumentList $Args -EnableException $True -debug -verbose
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