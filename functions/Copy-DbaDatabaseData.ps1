function Copy-DbaDatabaseData {
    [CmdletBinding()]
    param (
        [DbaInstanceParameter]
        $SqlInstance,

        [PSCredential]
        $SqlCredential,

        [DbaInstanceParameter]
        $Destination,

        [PSCredential]
        $DestinationSqlCredential,

        [string]
        $Database,

        [string]
        $DestinationDatabase,

        [string[]]
        $ExcludeDatabase,

        [int]
        $BatchSize = 50000,

        [int]
        $NotifyAfter = 5000,

        [int]
        $bulkCopyTimeOut = 5000,

        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]
        $InputObject,

        [switch] $AutoCreateTable,
        [switch] $NoTableLock,
        [switch] $EnableException
    )

    if (-not $InputObject) {
        $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException:$EnableException
    }

    foreach ($source in $InputObject) {
        if ($ExcludeDatabase -contains $source.Name) { continue; }
        if (-not $DestinationDatabase) { $DestinationDatabase = $source.Name }
        $target = Get-DbaDatabase -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -Database $DestinationDatabase -EnableException:$EnableException

        if ($target) {
            $ForeignKeys = Get-DbaDbTable -InputObject $target -EnableException:$EnableException |
            Where-Object { -not $_.IsSystemObject } |
            ForEach-Object ForeignKeys
            if ( $ForeignKeys ) {
                $ForeignKeyScript = $ForeignKeys.Script() | Out-String
                $ForeignKeys.Drop()
            }

            try {
                Get-DbaDbTable -InputObject $source -EnableException:$EnableException |
                Where-Object { -not $_.IsSystemObject } |
                Copy-DbaDbTableData -Destination $Destination -SqlCredential $DestinationSqlCredential -DestinationDatabase $DestinationDatabase -Truncate -KeepIdentity -KeepNulls -NoTableLock:$NoTableLock -AutoCreateTable:$AutoCreateTable -EnableException:$EnableException
            } finally {
                if ( $ForeignKeyScript ) {
                    Invoke-DbaQuery -InputObject $target -Query $ForeignKeyScript -EnableException:$EnableException
                }
            }
        }
    }
}