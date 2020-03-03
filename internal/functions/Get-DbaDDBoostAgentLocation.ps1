function Get-DbaDDBoostAgentLocation {
    <#
    .SYNOPSIS
        Returns the root installation path of the Data Domain Application Agent

    .DESCRIPTION
        Returns a string path of the Data Domain Application Agent

        Requires: Windows administrator access on Servers

    .PARAMETER ComputerName
        The target computer.

    .PARAMETER Credential
        Alternative credential

    .PARAMETER DataDomainAgentPath
        Allows for an overriding path to be verified

    .PARAMETER EnableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.
    .NOTES
        Tags: DDBoost
        Author: Stephen Swan (@jaxnoth)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDDBoostAgentLocation

    .EXAMPLE
        PS C:\> Get-DbaDDBoostAgentLocation -ComputerName srv001

        Get agent location on server srv001

    #>

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias('cn', 'host', 'Server')]
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [string] $DataDomainAgentPath,
        [switch]$EnableException
    )

    begin {

        If ($DataDomainAgentPath) {
            $agentPath = $DataDomainAgentPath
        } else {
            $Node = Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                $Node = Get-ItemProperty HKLM:\SOFTWARE\WOW6432Node\EMC\DDBMSS
                If (-Not $Node) {
                    $Node = Get-ItemProperty HKLM:\SOFTWARE\EMC\DDBMSS
                }
                return $Node
            }
            If ($Node) {
                $agentPath = $Node.Path
            }
        }
        if (-Not ($agentPath -and (Test-Path $agentPath -PathType Container))) {
            Stop-Function -Message "Cannot determine location of DDBoost Agent"
        }
        Write-Message -Message "DDBoost Agent Path: $agentPath" -Level Verbose
        return $agentPath
    }
}