function Join-SomePath {
    <#
    .SYNOPSIS
        Combines two path strings into a valid path without requiring path to exist.

    .DESCRIPTION
        Combines two path strings into a valid path without requiring path to exist.

        Handles all slash variants between the two strings.

    .PARAMETER Path
        First part of path

    .PARAMETER ChildPath
        Second part of path

    #>
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$ChildPath
    )
    process {
        [IO.Path]::Combine([string[]]@($Path, $ChildPath))
    }
}