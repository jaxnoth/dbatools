function New-DbaDbMergeProcedure {
    <#
    .SYNOPSIS
        Builds or returns a SQL Server Merge statement.

    .DESCRIPTION
        Builds or returns a SQL Server Merge statement. Note that dbatools-style syntax is used.

        So you do not need to specify "Data Source", you can just specify -SqlInstance and -SqlCredential and we'll handle it for you.

        This is the simplified PowerShell approach to merge procedure building. See examples for more info.

    .PARAMETER SqlInstance
        Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database to copy the table from.

    .PARAMETER DestinationDatabase
        The database to copy the table to. If not specified, it is assumed to be the same of Database

    .PARAMETER Table
        Define a specific table you would like to use as source. You can specify a three-part name like db.sch.tbl.
        If the object has special characters please wrap them in square brackets [ ].
        This dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
        The correct way to find table named 'First.Table' on schema 'dbo' is passing dbo.[First.Table]

    .PARAMETER DestinationTable
        The table you want to use as destination. If not specified, it is assumed to be the same of Table

    .PARAMETER Query
        If you want to merge only a portion of a table or selected tables, specify the query.
        Ensure to select all required columns. Calculated Columns or columns with default values may be excluded.
        The tablename should be a full three-part name in form [Database].[Schema].[Table]

    .PARAMETER JoinColumns
        Columns to join source and target tables via hash comparison.  Defaults to nonhashed primary key of destination table.

    .PARAMETER OnlyChanged
        If this switch is enabled, all columns are compared for changes.

    .PARAMETER AdditionalMatchedAction
        Can provide additional columns to update in target outside of source.

    .PARAMETER AdditionalNotMatchedByTargetAction
        Can provide additional columns to insert in target outside of source.

    .PARAMETER NotMatchedBySourceAction
        Defines what to do when target table does not have the data.  Defaults to DELETE

    .PARAMETER IncludedTypes
        Defines what sql data types columns must be to be included.
        Defaults to int,varchar,nvarchar,char,nchar,date,datetime,datetime2

    .PARAMETER ProcedureName
        This field causes a full merge procedure to be scripted using the given name instead of the merge sql statement.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
    #>

    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string]$Database,
        [string]$DestinationDatabase,
        [string]$Table,
        [string]$DestinationTable,
        [string]$Query,
        [string[]]$JoinColumns,
        [switch]$OnlyChanged,
        [string]$AdditionalMatchedAction,
        [string]$AdditionalNotMatchedByTargetAction,
        [string]$NotMatchedBySourceAction = 'DELETE',
        [string]$IncludedTypes = 'int,varchar,nvarchar,char,nchar,date,datetime,datetime2',
        [string]$ProcedureName,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject
    )

    begin {
    }
    process {
        if ((Test-Bound -Not -ParameterName Table, SqlInstance) -and (Test-Bound -Not -ParameterName InputObject)) {
            Stop-Function -Message "You must pipe in a table or specify SqlInstance, Database and Table."
            return
        }

        if ($SqlInstance) {
            if ((Test-Bound -Not -ParameterName Database)) {
                Stop-Function -Message "Database is required when passing a SqlInstance" -Target $Table
                return
            }

            if ((Test-Bound -Not -ParameterName Destination, DestinationDatabase, DestinationTable)) {
                Stop-Function -Message "Cannot copy $Table into itself. One of destination Server, Database or Table must be specified " -Target $Table
                return
            }

            try {
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            if ($Database -notin $server.Databases.Name) {
                Stop-Function -Message "Database $Database doesn't exist on $server"
                return
            }

            try {
                $dbTable = Get-DbaDbTable -SqlInstance $server -Table $Table -Database $Database -EnableException -Verbose:$false
                if ($dbTable.Count -eq 1) {
                    $InputObject += $dbTable
                } else {
                    Stop-Function -Message "The table $Table matches $($dbTable.Count) objects. Unable to determine which object to copy" -Continue
                }
            } catch {
                Stop-Function -Message "Unable to determine source table : $Table"
                return
            }
        }

        foreach ($sqltable in $InputObject) {
            $Database = $sqltable.Parent.Name
            $server = $sqltable.Parent.Parent

            if ((Test-Bound -Not -ParameterName DestinationTable)) {
                $DestinationTable = '[' + $sqltable.Schema + '].[' + $sqltable.Name + ']'
            }

            $newTableParts = Get-ObjectNameParts -ObjectName $DestinationTable
            #using FQTN to determine database name
            if ($newTableParts.Database) {
                $DestinationDatabase = $newTableParts.Database
            } elseif ((Test-Bound -Not -ParameterName DestinationDatabase)) {
                $DestinationDatabase = $Database
            }

            if (-not $Destination) {
                $Destination = $server
            }

            foreach ($destinationserver in $Destination) {
                try {
                    $destServer = Connect-SqlInstance -SqlInstance $destinationserver -SqlCredential $DestinationSqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $destinationserver
                    return
                }

                if ($DestinationDatabase -notin $destServer.Databases.Name) {
                    Stop-Function -Message "Database $DestinationDatabase doesn't exist on $destServer"
                    return
                }

                $desttable = Get-DbaDbTable -SqlInstance $destServer -Table $DestinationTable -Database $DestinationDatabase -Verbose:$false | Select-Object -First 1

                if (-not $desttable) {
                    Stop-Function -Message "Table $DestinationTable cannot be found in $DestinationDatabase. Use -AutoCreateTable to automatically create the table on the destination." -Continue
                }

                $connstring = $destServer.ConnectionContext.ConnectionString

                if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $fqtnfrom = "$sqltable"
                } else {
                    $fqtnfrom = "$($server.Databases[$Database]).$sqltable"
                }

                if ($destServer.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $fqtndest = "$desttable"
                } else {
                    $fqtndest = "$($destServer.Databases[$DestinationDatabase]).$desttable"
                }

                if ($fqtndest -eq $fqtnfrom -and $server.Name -eq $destServer.Name -and (Test-Bound -ParameterName Query -Not)) {
                    Stop-Function -Message "Cannot copy $fqtnfrom on $($server.Name) into $fqtndest on ($destServer.Name). Source and Destination must be different " -Target $Table
                    return
                }

                if (Test-Bound -ParameterName Query -Not) {
                    $Query = "SELECT * FROM $fqtnfrom"
                    $sourceLabel = $fqtnfrom
                } else {
                    $sourceLabel = "Query"
                }
                try {
                    $MergeStmt = "
                    MERGE INTO [dbo].[LMS_DiscussionForums] AS T
                    USING [dbo].[LMS_StagedDiscussionForums] AS S
                        ON T.[ForumId] = S.[ForumId]
                     WHEN MATCHED
                        THEN
                            UPDATE
                            SET T.[OrgUnitId] = CAST(S.[OrgUnitId] AS INT)
                                , T.[ForumId] = CAST(S.[ForumId] AS INT)
                                , T.[Name] = CAST(S.[Name] AS nvarchar(1000))
                                , T.[Description] = CAST(S.[Description] AS nvarchar(1000))
                                , T.[VisibleStartDate] = CAST(S.[VisibleStartDate] AS datetime2)
                                , T.[VisibleEndDate] = CAST(S.[VisibleEndDate] AS datetime2)
                                , T.[PostingStartDate] = CAST(S.[PostingStartDate] AS datetime2)
                                , T.[PostingEndDate] = CAST(S.[PostingEndDate] AS datetime2)
                                , T.[MustPostToParticipate] = CASE S.[MustPostToParticipate] WHEN 'False' THEN 0 ELSE 1 END
                                , T.[AllowAnon] = CASE S.[AllowAnon] WHEN 'False' THEN 0 ELSE 1 END
                                , T.[IsHidden] = CASE S.[IsHidden] WHEN 'False' THEN 0 ELSE 1 END
                                , T.[RequiresApproval] = CASE S.[RequiresApproval] WHEN 'False' THEN 0 ELSE 1 END
                                , T.[SortOrder] = CAST(S.[SortOrder] AS INT)
                                , T.[IsDeleted] = CASE S.[IsDeleted] WHEN 'False' THEN 0 ELSE 1 END
                                , T.[DeletedDate] = CAST(S.[DeletedDate] AS datetime2)
                                , T.[DeletedByUserId] = CAST(S.[DeletedByUserId] AS INT)
                                , T.[ResultId] = CAST(S.[ResultId] AS INT)
                                , T.[Valid] = 1
                    WHEN NOT MATCHED BY TARGET
                        THEN
                            INSERT (
                                [OrgUnitId]
                                , [ForumId]
                                , [Name]
                                , [Description]
                                , [VisibleStartDate]
                                , [VisibleEndDate]
                                , [PostingStartDate]
                                , [PostingEndDate]
                                , [MustPostToParticipate]
                                , [AllowAnon]
                                , [IsHidden]
                                , [RequiresApproval]
                                , [SortOrder]
                                , [IsDeleted]
                                , [DeletedDate]
                                , [DeletedByUserId]
                                , [ResultId]
                                , Valid
                                )
                            VALUES (
                                CAST(S.[OrgUnitId] AS INT)
                                , CAST(S.[ForumId] AS INT)
                                , CAST(S.[Name] AS nvarchar(1000))
                                , CAST(S.[Description] AS nvarchar(1000))
                                , CAST(S.[VisibleStartDate] AS datetime2)
                                , CAST(S.[VisibleEndDate] AS datetime2)
                                , CAST(S.[PostingStartDate] AS datetime2)
                                , CAST(S.[PostingEndDate] AS datetime2)
                                , CASE S.[MustPostToParticipate] WHEN 'False' THEN 0 ELSE 1 END
                                , CASE S.[AllowAnon] WHEN 'False' THEN 0 ELSE 1 END
                                , CASE S.[IsHidden] WHEN 'False' THEN 0 ELSE 1 END
                                , CASE S.[RequiresApproval] WHEN 'False' THEN 0 ELSE 1 END
                                , CAST(S.[SortOrder] AS INT)
                                , CASE S.[IsDeleted] WHEN 'False' THEN 0 ELSE 1 END
                                , CAST(S.[DeletedDate] AS datetime2)
                                , CAST(S.[DeletedByUserId] AS INT)
                                , CAST(S.[ResultId] AS INT)
                                , 1
                                )
                    WHEN NOT MATCHED BY SOURCE
                        THEN UPDATE
                            SET Valid = (~ @Validate) & (Valid)

                    "
                    [pscustomobject]@{
                        SourceInstance      = $server.Name
                        SourceDatabase      = $Database
                        SourceSchema        = $sqltable.Schema
                        SourceTable         = $sqltable.Name
                        DestinationInstance = $destServer.Name
                        DestinationDatabase = $DestinationDatabase
                        DestinationSchema   = $desttable.Schema
                        DestinationTable    = $desttable.Name
                        RowsCopied          = $rowstotal
                        Elapsed             = [prettytimespan]$elapsed.Elapsed
                    }
                } catch {
                    Stop-Function -Message "Something went wrong" -ErrorRecord $_ -Target $server -continue
                }

            }
        }

        <#
IF ((@cols_to_join_on IS NOT NULL) AND (PATINDEX('''%''',@cols_to_join_on) = 0))
 BEGIN
 RAISERROR('Invalid use of @cols_to_join_on property',16,1)
 PRINT 'Specify column names surrounded by single quotes and separated by commas'
 PRINT 'Eg: EXEC sp_generate_merge "StateProvince", @schema = "Person", @cols_to_join_on = "''StateProvinceCode''"'
 RETURN -1 --Failure. Reason: Invalid use of @cols_to_join_on property
 END

 IF @hash_compare_column IS NOT NULL AND @update_only_if_changed = 0
 BEGIN
	RAISERROR('Invalid use of @update_only_if_changed property',16,1)
	PRINT 'The @hash_compare_column param is set, however @update_only_if_changed is set to 0. To utilize hash-based change detection, please ensure @update_only_if_changed is set to 1.'
	RETURN -1 --Failure. Reason: Invalid use of @update_only_if_changed property
 END

 IF @hash_compare_column IS NOT NULL AND @include_values = 1
 BEGIN
	RAISERROR('Invalid use of @include_values',16,1)
	PRINT 'Using @hash_compare_column together with @include_values is currenty unsupported. Our intention is to support this in the future, however for now @hash_compare_column can only be specified when @include_values=0'
	RETURN -1 --Failure. Reason: Invalid use of @include_values property
 END

--Checking to see if the database name is specified along wih the table name
--Your database context should be local to the table for which you want to generate a MERGE statement
--specifying the database name is not allowed
IF (PARSENAME(@table_name,3)) IS NOT NULL
 BEGIN
 RAISERROR('Do not specify the database name. Be in the required database and just specify the table name.',16,1)
 RETURN -1 --Failure. Reason: Database name is specified along with the table name, which is not allowed
 END


DECLARE @Internal_Table_Name NVARCHAR(128)
IF PARSENAME(@table_name,1) LIKE '#%'
BEGIN
	IF DB_NAME() <> 'tempdb'
	BEGIN
		RAISERROR('Incorrect database context. The proc must be executed against [tempdb] when a temporary table is specified.',16,1)
		PRINT 'To resolve, execute the proc in the context of [tempdb], e.g. EXEC tempdb.dbo.sp_generate_merge @table_name=''' + @table_name + ''''
		RETURN -1 --Failure. Reason: Temporary tables cannot be referenced in a user db
	END
	SET @Internal_Table_Name = (SELECT [name] FROM sys.objects WHERE [object_id] = OBJECT_ID(@table_name))
END
ELSE
BEGIN
	SET @Internal_Table_Name = @table_name
END

--Variable declarations
DECLARE @Column_ID int,
 @Column_List nvarchar(max),
 @Column_List_For_Update nvarchar(max),
 @Column_List_For_Check nvarchar(max),
 @Column_Name nvarchar(128),
 @Column_Name_Unquoted nvarchar(128),
 @Data_Type nvarchar(128),
 @Actual_Values nvarchar(max), --This is the string that will be finally executed to generate a MERGE statement
 @IDN nvarchar(128), --Will contain the IDENTITY column's name in the table
 @Target_Table_For_Output nvarchar(776),
 @Source_Table_Qualified nvarchar(776),
 @Source_Table_For_Output nvarchar(776),
 @sql nvarchar(max),  --SQL statement that will be executed to check existence of [Hashvalue] column in case @hash_compare_column is used
 @checkhashcolumn nvarchar(128),
 @SourceHashColumn bit = 0,
 @b char(1) = char(13)

 IF @hash_compare_column IS NOT NULL  --Check existence of column [Hashvalue] in target table and raise error in case of missing
 BEGIN
 IF @target_table IS NULL
 BEGIN
	SET @target_table = @table_name
 END
 SET @SQL =
	'SELECT @columnname = column_name
	FROM ' + COALESCE(PARSENAME(@target_table,3),DB_NAME()) + '.INFORMATION_SCHEMA.COLUMNS (NOLOCK)
	WHERE TABLE_NAME = ''' + PARSENAME(@target_table,1) + '''' +
	' AND TABLE_SCHEMA = ' + '''' + COALESCE(@schema, SCHEMA_NAME()) + '''' + ' AND [COLUMN_NAME] = ''' + @hash_compare_column + ''''

	EXECUTE sp_executesql @sql, N'@columnname nvarchar(128) OUTPUT', @columnname = @checkhashcolumn OUTPUT
	IF @checkhashcolumn IS NULL
	BEGIN
	  RAISERROR('Column %s not found ',16,1, @hash_compare_column)
	  PRINT 'The specified @hash_compare_column [' + @hash_compare_column +  '] does not exist in ' + QUOTENAME(@target_table) + '. Please make sure that [' + @hash_compare_column + '] VARBINARY (8000) exits in the target table'
	  RETURN -1 --Failure. Reason: There is no column that can be used as the basis of Hashcompare
	END

 END


--Variable Initialization
SET @IDN = ''
SET @Column_ID = 0
SET @Column_Name = ''
SET @Column_Name_Unquoted = ''
SET @Column_List = ''
SET @Column_List_For_Update = ''
SET @Column_List_For_Check = ''
SET @Actual_Values = ''

--Variable Defaults
IF @target_table IS NOT NULL AND (@target_table LIKE '%.%' OR @target_table LIKE '\[%\]' ESCAPE '\')
BEGIN
 IF NOT @target_table LIKE '\[%\]' ESCAPE '\'
 BEGIN
  RAISERROR('Ambiguous value for @target_table specified. Use QUOTENAME() to ensure the identifer is fully qualified (e.g. [dbo].[Titles] or [OtherDb].[dbo].[Titles]).',16,1)
  RETURN -1 --Failure. Reason: The value could be a multi-part object identifier or it could be a single-part object identifier that just happens to include a period character
 END

 -- If the user has specified the @schema param, but the qualified @target_table they've specified does not include the target schema, then fail validation to avoid any ambiguity
 IF @schema IS NOT NULL AND @target_table NOT LIKE '%.%'
 BEGIN
  RAISERROR('The specified @target_table is missing a schema name (e.g. [dbo].[Titles]).',16,1)
  RETURN -1 --Failure. Reason: Omitting the schema in this scenario is likely a mistake
 END

  SET @Target_Table_For_Output = @target_table
 END
 ELSE
 BEGIN
 IF @schema IS NULL
 BEGIN
  SET @Target_Table_For_Output = QUOTENAME(COALESCE(@target_table, @table_name))
 END
 ELSE
 BEGIN
  SET @Target_Table_For_Output = QUOTENAME(@schema) + '.' + QUOTENAME(COALESCE(@target_table, @table_name))
 END
END

SET @Source_Table_Qualified = QUOTENAME(COALESCE(@schema,SCHEMA_NAME())) + '.' + QUOTENAME(@Internal_Table_Name)
SET @Source_Table_For_Output = QUOTENAME(COALESCE(@schema,SCHEMA_NAME())) + '.' + QUOTENAME(@table_name)

--To get the first column's ID
SELECT @Column_ID = MIN(ORDINAL_POSITION)
FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)
WHERE TABLE_NAME = @Internal_Table_Name
AND TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())


--Loop through all the columns of the table, to get the column names and their data types
WHILE @Column_ID IS NOT NULL
 BEGIN
 SELECT @Column_Name = QUOTENAME(COLUMN_NAME),
 @Column_Name_Unquoted = COLUMN_NAME,
 @Data_Type = DATA_TYPE
 FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)
 WHERE ORDINAL_POSITION = @Column_ID
 AND TABLE_NAME = @Internal_Table_Name
 AND TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())


IF @Data_Type IN ('timestamp','rowversion') --SQL Server doesn't allow Timestamp/Rowversion column updates
BEGIN
	GOTO SKIP_LOOP
END

 IF @cols_to_include IS NOT NULL --Selecting only user specified columns
 BEGIN
 IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_include) = 0
 BEGIN
 GOTO SKIP_LOOP
 END
 END

 IF @cols_to_exclude IS NOT NULL --Selecting only user specified columns
 BEGIN
 IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_exclude) <> 0
 BEGIN
 GOTO SKIP_LOOP
 END
 END

 --Making sure to output SET IDENTITY_INSERT ON/OFF in case the table has an IDENTITY column
 IF (SELECT COLUMNPROPERTY( OBJECT_ID(@Source_Table_Qualified),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsIdentity')) = 1
 BEGIN
 IF @ommit_identity = 0 --Determing whether to include or exclude the IDENTITY column
 SET @IDN = @Column_Name
 ELSE
 GOTO SKIP_LOOP
 END

 --Making sure whether to output computed columns or not
 IF @ommit_computed_cols = 1
 BEGIN
 IF (SELECT COLUMNPROPERTY( OBJECT_ID(@Source_Table_Qualified),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsComputed')) = 1
 BEGIN
 PRINT 'Warning: The ' + @Column_Name + ' computed column will be excluded from the MERGE statement. Specify @ommit_computed_cols = 0 to include computed columns.'
 GOTO SKIP_LOOP
 END
 END

 --Skip this column if it is the GENERATED ALWAYS type, unless the user specifically wants those types of columns included
 IF @ommit_generated_always_cols = 1
 IF ISNULL((SELECT COLUMNPROPERTY( OBJECT_ID(@Source_Table_Qualified),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'GeneratedAlwaysType')), 0) <> 0
 BEGIN
 PRINT 'Warning: The ' + @Column_Name + ' GENERATED ALWAYS column will be excluded from the MERGE statement. Specify @ommit_generated_always_cols = 0 to include GENERATED ALWAYS columns.'
 GOTO SKIP_LOOP
 END

 --make sure if source table already contains @hash_compare_column to avoid being doubled in UPDATE clause
 IF  @hash_compare_column IS NOT NULL AND @Column_Name = QUOTENAME(@hash_compare_column)
 BEGIN
	SET @SourceHashColumn = 1
 END

 --Tables with columns of IMAGE data type are not supported for obvious reasons
 IF(@Data_Type in ('image'))
 BEGIN
 IF (@ommit_images = 0)
 BEGIN
 RAISERROR('Tables with image columns are not supported.',16,1)
 PRINT 'Use @ommit_images = 1 parameter to generate a MERGE for the rest of the columns.'
 RETURN -1 --Failure. Reason: There is a column with image data type
 END
 ELSE
 BEGIN
 GOTO SKIP_LOOP
 END
 END

 --Determining the data type of the column and depending on the data type, the VALUES part of
 --the MERGE statement is generated. Care is taken to handle columns with NULL values. Also
 --making sure, not to lose any data from flot, real, money, smallmomey, datetime columns
 SET @Actual_Values = @Actual_Values +
 CASE
 WHEN @Data_Type IN ('char','nchar')
 THEN
 'COALESCE(''N'''''' + REPLACE(RTRIM(' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('varchar','nvarchar')
 THEN
 'COALESCE(''N'''''' + REPLACE(' + @Column_Name + ','''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('datetime','smalldatetime','datetime2','date', 'datetimeoffset')
 THEN
 'COALESCE('''''''' + RTRIM(CONVERT(char,' + @Column_Name + ',127))+'''''''',''NULL'')'
 WHEN @Data_Type IN ('uniqueidentifier')
 THEN
 'COALESCE(''N'''''' + REPLACE(CONVERT(char(36),RTRIM(' + @Column_Name + ')),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('text')
 THEN
 'COALESCE(''N'''''' + REPLACE(CONVERT(varchar(max),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('ntext')
 THEN
 'COALESCE('''''''' + REPLACE(CONVERT(nvarchar(max),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('xml')
 THEN
 'COALESCE('''''''' + REPLACE(CONVERT(nvarchar(max),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'
 WHEN @Data_Type IN ('binary','varbinary')
 THEN
 'COALESCE(RTRIM(CONVERT(varchar(max),' + @Column_Name + ', 1)),''NULL'')'
 WHEN @Data_Type IN ('float','real','money','smallmoney')
 THEN
 'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' + @Column_Name + ',2)' + ')),''NULL'')'
 WHEN @Data_Type IN ('hierarchyid')
 THEN
  'COALESCE(''hierarchyid::Parse(''+'''''''' + LTRIM(RTRIM(' + 'CONVERT(char, ' + @Column_Name + ')' + '))+''''''''+'')'',''NULL'')'
 WHEN @Data_Type IN ('geography')
 THEN
  'COALESCE(''geography::STGeomFromText(''+'''''''' + LTRIM(RTRIM(' + 'CONVERT(nvarchar(max),' + @Column_Name + ')' + '))+''''''''+'', 4326)'',''NULL'')'
 WHEN @Data_Type IN ('geometry')
 THEN
  'COALESCE(''geometry::Parse(''+'''''''' + LTRIM(RTRIM(' + 'CONVERT(nvarchar(max),' + @Column_Name + ')' + '))+''''''''+'')'',''NULL'')'
 ELSE
 'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' + @Column_Name + ')' + ')),''NULL'')'
 END + '+' + ''',''' + ' + '

 --Generating the column list for the MERGE statement
 SET @Column_List = @Column_List +
 CASE WHEN @hash_compare_column IS NOT NULL AND @Column_Name = QUOTENAME(@hash_compare_column)
 THEN ''
 ELSE @Column_Name + ',' END

 --Don't update Primary Key or Identity columns
 IF NOT EXISTS(
 SELECT 1
 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk ,
 INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
 WHERE pk.TABLE_NAME = @Internal_Table_Name
 AND pk.TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
 AND CONSTRAINT_TYPE = 'PRIMARY KEY'
 AND c.TABLE_NAME = pk.TABLE_NAME
 AND c.TABLE_SCHEMA = pk.TABLE_SCHEMA
 AND c.CONSTRAINT_NAME = pk.CONSTRAINT_NAME
 AND c.COLUMN_NAME = @Column_Name_Unquoted
 )
 BEGIN
  SET @Column_List_For_Update = @Column_List_For_Update + '[Target].' + @Column_Name + ' = [Source].' + @Column_Name + ', ' + @b + '  '
 SET @Column_List_For_Check = @Column_List_For_Check +
 CASE @Data_Type
 WHEN 'text' THEN CHAR(10) + CHAR(9) + 'NULLIF(CAST([Source].' + @Column_Name + ' AS VARCHAR(MAX)), CAST([Target].' + @Column_Name + ' AS VARCHAR(MAX))) IS NOT NULL OR NULLIF(CAST([Target].' + @Column_Name + ' AS VARCHAR(MAX)), CAST([Source].' + @Column_Name + ' AS VARCHAR(MAX))) IS NOT NULL OR '
 WHEN 'ntext' THEN CHAR(10) + CHAR(9) + 'NULLIF(CAST([Source].' + @Column_Name + ' AS NVARCHAR(MAX)), CAST([Target].' + @Column_Name + ' AS NVARCHAR(MAX))) IS NOT NULL OR NULLIF(CAST([Target].' + @Column_Name + ' AS NVARCHAR(MAX)), CAST([Source].' + @Column_Name + ' AS NVARCHAR(MAX))) IS NOT NULL OR '
 WHEN 'geography' THEN CHAR(10) + CHAR(9) + '((NOT ([Source].' + @Column_Name + ' IS NULL AND [Target].' + @Column_Name + ' IS NULL)) AND ISNULL(ISNULL([Source].' + @Column_Name + ', geography::[Null]).STEquals([Target].' + @Column_Name + '), 0) = 0) OR '
 WHEN 'geometry' THEN CHAR(10) + CHAR(9) + '((NOT ([Source].' + @Column_Name + ' IS NULL AND [Target].' + @Column_Name + ' IS NULL)) AND ISNULL(ISNULL([Source].' + @Column_Name + ', geometry::[Null]).STEquals([Target].' + @Column_Name + '), 0) = 0) OR '
 ELSE CHAR(10) + CHAR(9) + 'NULLIF([Source].' + @Column_Name + ', [Target].' + @Column_Name + ') IS NOT NULL OR NULLIF([Target].' + @Column_Name + ', [Source].' + @Column_Name + ') IS NOT NULL OR '
 END
 END

 SKIP_LOOP: --The label used in GOTO

 SELECT @Column_ID = MIN(ORDINAL_POSITION)
 FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)
 WHERE TABLE_NAME = @Internal_Table_Name
 AND TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
 AND ORDINAL_POSITION > @Column_ID

 END --Loop ends here!


--To get rid of the extra characters that got concatenated during the last run through the loop
IF LEN(@Column_List_For_Update) <> 0
 BEGIN
 SET @Column_List_For_Update = ' ' + LEFT(@Column_List_For_Update,len(@Column_List_For_Update) - 3)
 END

IF LEN(@Column_List_For_Check) <> 0
 BEGIN
 SET @Column_List_For_Check = LEFT(@Column_List_For_Check,len(@Column_List_For_Check) - 3)
 END

SET @Actual_Values = LEFT(@Actual_Values,len(@Actual_Values) - 6)

SET @Column_List = LEFT(@Column_List,len(@Column_List) - 1)
IF LEN(LTRIM(@Column_List)) = 0
 BEGIN
 RAISERROR('No columns to select. There should at least be one column to generate the output',16,1)
 RETURN -1 --Failure. Reason: Looks like all the columns are ommitted using the @cols_to_exclude parameter
 END


--Get the join columns ----------------------------------------------------------
DECLARE @PK_column_list NVARCHAR(max)
DECLARE @PK_column_joins NVARCHAR(max)
SET @PK_column_list = ''
SET @PK_column_joins = ''

IF ISNULL(@cols_to_join_on, '') = '' -- Use primary key of the source table as the basis of MERGE joins, if no join list is specified
BEGIN
	SELECT @PK_column_list = @PK_column_list + '[' + c.COLUMN_NAME + '], '
	, @PK_column_joins = @PK_column_joins + '[Target].[' + c.COLUMN_NAME + '] = [Source].[' + c.COLUMN_NAME + '] AND '
	FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk ,
	INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
	WHERE pk.TABLE_NAME = @Internal_Table_Name
	AND pk.TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
	AND CONSTRAINT_TYPE = 'PRIMARY KEY'
	AND c.TABLE_NAME = pk.TABLE_NAME
	AND c.TABLE_SCHEMA = pk.TABLE_SCHEMA
	AND c.CONSTRAINT_NAME = pk.CONSTRAINT_NAME
END
ELSE
BEGIN
	SELECT @PK_column_list = @PK_column_list + '[' + c.COLUMN_NAME + '], '
	, @PK_column_joins = @PK_column_joins + '[Target].[' + c.COLUMN_NAME + '] = [Source].[' + c.COLUMN_NAME + '] AND '
	FROM INFORMATION_SCHEMA.COLUMNS AS c
	WHERE @cols_to_join_on LIKE '%''' + c.COLUMN_NAME + '''%'
	AND c.TABLE_NAME = @Internal_Table_Name
	AND c.TABLE_SCHEMA = COALESCE(@schema, SCHEMA_NAME())
END

IF ISNULL(@PK_column_list, '') = ''
BEGIN
	RAISERROR('Table does not have a primary key from which to generate the join clause(s) and/or a valid @cols_to_join_on has not been specified. Either add a primary key/composite key to the table or specify the @cols_to_join_on parameter.',16,1)
	RETURN -1 --Failure. Reason: looks like table doesn't have any primary keys
END

SET @PK_column_list = LEFT(@PK_column_list, LEN(@PK_column_list) -1)
SET @PK_column_joins = LEFT(@PK_column_joins, LEN(@PK_column_joins) -4)


--Forming the final string that will be executed, to output the a MERGE statement
SET @Actual_Values =
 'SELECT ' +
 CASE WHEN @top IS NULL OR @top < 0 THEN '' ELSE ' TOP ' + LTRIM(STR(@top)) + ' ' END +
 '''' +
 ' '' + CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) = 1 THEN '' '' ELSE '','' END + ''(''+ ' + @Actual_Values + '+'')''' + ' ' +
 COALESCE(@from,' FROM ' + @Source_Table_Qualified + ' (NOLOCK) ORDER BY ' + @PK_column_list)

 SET @output = CASE WHEN ISNULL(@results_to_text, 1) = 1 THEN '' ELSE '---' END


--Determining whether to ouput any debug information
IF @debug_mode =1
 BEGIN
 SET @output += @b + '/*****START OF DEBUG INFORMATION*****'
 SET @output += @b + ''
 SET @output += @b + 'The primary key column list:'
 SET @output += @b + @PK_column_list
 SET @output += @b + ''
 SET @output += @b + 'The INSERT column list:'
 SET @output += @b + @Column_List
 SET @output += @b + ''
 SET @output += @b + 'The UPDATE column list:'
 SET @output += @b + @Column_List_For_Update
 SET @output += @b + ''
 SET @output += @b + 'The SELECT statement executed to generate the MERGE:'
 SET @output += @b + @Actual_Values
 SET @output += @b + ''
 SET @output += @b + '*****END OF DEBUG INFORMATION*****/'
 SET @output += @b + ''
 END

IF (@include_use_db = 1)
 BEGIN
	SET @output += @b
	SET @output += @b + 'USE [' + DB_NAME() + ']'
	SET @output += @b + ISNULL(@batch_separator, '')
	SET @output += @b
 END

IF (@nologo = 0)
 BEGIN
 SET @output += @b + '--MERGE generated by ''sp_generate_merge'' stored procedure'
 SET @output += @b + '--Originally by Vyas (http://vyaskn.tripod.com/code): sp_generate_inserts (build 22)'
 SET @output += @b + '--Adapted for SQL Server 2008+ by Daniel Nolan (https://twitter.com/dnlnln)'
 SET @output += @b + ''
 END

IF (@include_rowsaffected = 1) -- If the caller has elected not to include the "rows affected" section, let MERGE output the row count as it is executed.
 SET @output += @b + 'SET NOCOUNT ON'
 SET @output += @b + ''


--Determining whether to print IDENTITY_INSERT or not
IF (LEN(@IDN) <> 0)
 BEGIN
 SET @output += @b + 'SET IDENTITY_INSERT ' + @Target_Table_For_Output + ' ON'
 SET @output += @b + ''
 END


--Temporarily disable constraints on the target table
DECLARE @output_enable_constraints NVARCHAR(MAX) = ''
DECLARE @ignore_disable_constraints BIT = IIF((OBJECT_ID(@Source_Table_Qualified, 'U') IS NULL), 1, 0)
IF @disable_constraints = 1 AND @ignore_disable_constraints = 1
BEGIN
	PRINT 'Warning: @disable_constraints=1 will be ignored as the source table does not exist'
END
ELSE IF @disable_constraints = 1
BEGIN
	DECLARE @Source_Table_Constraints TABLE ([name] SYSNAME PRIMARY KEY, [is_not_trusted] bit, [is_disabled] bit)
	INSERT INTO @Source_Table_Constraints ([name], [is_not_trusted], [is_disabled])
	SELECT [name], [is_not_trusted], [is_disabled] FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID(@Source_Table_Qualified, 'U')
	UNION
	SELECT [name], [is_not_trusted], [is_disabled] FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID(@Source_Table_Qualified, 'U')

	DECLARE @Constraint_Ct INT = (SELECT COUNT(1) FROM @Source_Table_Constraints)
	IF @Constraint_Ct = 0
	BEGIN
		PRINT 'Warning: @disable_constraints=1 will be ignored as there are no foreign key or check constraints on the source table'
		SET @ignore_disable_constraints = 1
	END
	ELSE IF ((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_disabled] = 1) = (SELECT COUNT(1) FROM @Source_Table_Constraints))
	BEGIN
		PRINT 'Warning: @disable_constraints=1 will be ignored as all foreign key and/or check constraints on the source table are currently disabled'
		SET @ignore_disable_constraints = 1
	END
	ELSE
	BEGIN
		DECLARE @All_Constraints_Enabled BIT = IIF((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_disabled] = 0) = @Constraint_Ct, 1, 0)
		DECLARE @All_Constraints_Trusted BIT = IIF((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_not_trusted] = 0) = @Constraint_Ct, 1, 0)
		DECLARE @All_Constraints_NotTrusted BIT = IIF((SELECT COUNT(1) FROM @Source_Table_Constraints WHERE [is_not_trusted] = 1) = @Constraint_Ct, 1, 0)

		IF @All_Constraints_Enabled = 1 AND @All_Constraints_Trusted = 1
		BEGIN
			SET @output += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' NOCHECK CONSTRAINT ALL' -- Disable constraints temporarily
			SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' WITH CHECK CHECK CONSTRAINT ALL' -- Enable the previously disabled constraints and re-check all data
		END
		ELSE IF @All_Constraints_Enabled = 1 AND @All_Constraints_NotTrusted = 1
		BEGIN
			SET @output += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' NOCHECK CONSTRAINT ALL' -- Disable constraints temporarily
			SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' CHECK CONSTRAINT ALL' -- Enable the previously disabled constraints, but don't re-check data
		END
		ELSE
		BEGIN
			-- Selectively enable/disable constraints, with/without WITH CHECK, on a case-by-case basis
			WHILE ((SELECT COUNT(1) FROM @Source_Table_Constraints) != 0)
			BEGIN
				DECLARE @Constraint_Item_Name SYSNAME = (SELECT TOP 1 [name] FROM @Source_Table_Constraints)
				DECLARE @Constraint_Item_IsDisabled BIT = (SELECT TOP 1 [is_disabled] FROM @Source_Table_Constraints)
				DECLARE @Constraint_Item_IsNotTrusted BIT = (SELECT TOP 1 [is_not_trusted] FROM @Source_Table_Constraints)

				IF (@Constraint_Item_IsDisabled = 1)
				BEGIN
					DELETE FROM @Source_Table_Constraints WHERE [name] = @Constraint_Item_Name -- Don't enable this previously-disabled constraint
					CONTINUE;
				END

				SET @output += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' NOCHECK CONSTRAINT ' + QUOTENAME(@Constraint_Item_Name)
				IF (@Constraint_Item_IsNotTrusted = 1)
				BEGIN
					SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' CHECK CONSTRAINT ' + QUOTENAME(@Constraint_Item_Name) -- Enable the previously disabled constraint, but don't re-check data
				END
				ELSE
				BEGIN
					SET @output_enable_constraints += @b + 'ALTER TABLE ' + @Target_Table_For_Output + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(@Constraint_Item_Name) -- Enable the previously disabled constraint and re-check all data
				END

				DELETE FROM @Source_Table_Constraints WHERE [name] = @Constraint_Item_Name
			END
		END
	END
END


--Output the start of the MERGE statement, qualifying with the schema name only if the caller explicitly specified it
SET @output += @b + 'MERGE INTO ' + @Target_Table_For_Output + ' AS [Target]'

IF @include_values = 1
BEGIN
 SET @output += @b + 'USING ('
 --All the hard work pays off here!!! You'll get your MERGE statement, when the next line executes!
 DECLARE @tab TABLE (ID INT NOT NULL PRIMARY KEY IDENTITY(1,1), val NVARCHAR(max));
 INSERT INTO @tab (val)
 EXEC (@Actual_Values)

 IF (SELECT COUNT(*) FROM @tab) <> 0 -- Ensure that rows were returned, otherwise the MERGE statement will get nullified.
 BEGIN
  SET @output += 'VALUES' + CAST((SELECT @b + val FROM @tab ORDER BY ID FOR XML PATH('')) AS XML).value('.', 'NVARCHAR(MAX)');
 END
 ELSE
 BEGIN
  -- Mimic an empty result set by returning zero rows from the target table
  SET @output += 'SELECT ' + @Column_List + ' FROM ' + @Target_Table_For_Output + ' WHERE 1 = 0 -- Empty dataset (source table contained no rows at time of MERGE generation) '
 END

 --Output the columns to correspond with each of the values above--------------------
 SET @output += @b + ') AS [Source] (' + @Column_List + ')'
END
ELSE
 IF @hash_compare_column IS NULL
 BEGIN
  SET @output += @b + 'USING ' + @Source_Table_For_Output + ' AS [Source]';
 END
 ELSE
 BEGIN
  SET @output += @b + 'USING (SELECT ' + @Column_List + ', HASHBYTES(''SHA2_256'', CONCAT(' + REPLACE(@Column_List,'],[','],''|'',[') +')) AS [' + @hash_compare_column  + '] FROM ' + @Source_Table_For_Output + ') AS [Source]'
 END

--Output the join columns ----------------------------------------------------------
SET @output += @b + 'ON (' + @PK_column_joins + ')'


--When matched, perform an UPDATE on any metadata columns only (ie. not on PK)------
IF LEN(@Column_List_For_Update) <> 0
BEGIN
 --Adding column @hash_compare_column to @ColumnList and @Column_List_For_Update if @hash_compare_column is not null
 IF @update_only_if_changed = 1 AND @hash_compare_column IS NOT NULL AND @SourceHashColumn = 0
 BEGIN
	SET @Column_List_For_Update = @Column_List_For_Update + ',' + @b + '  [Target].[' + @hash_compare_column +'] = [Source].[' + @hash_compare_column +']'
	SET @Column_List = @Column_List + ',[' + @hash_compare_column + ']'
 END
 SET @output += @b + 'WHEN MATCHED ' +
	 CASE WHEN @update_only_if_changed = 1 AND @hash_compare_column IS NOT NULL
	 THEN 'AND ([Target].[' + @hash_compare_column +'] <> [Source].[' + @hash_compare_column +'] OR [Target].[' + @hash_compare_column + '] IS NULL) '
	 ELSE CASE WHEN @update_only_if_changed = 1 AND @hash_compare_column IS NULL THEN
	 'AND (' + @Column_List_For_Check + ') ' ELSE '' END END + 'THEN'
 SET @output += @b + ' UPDATE SET'
 SET @output += @b + '  ' + LTRIM(@Column_List_For_Update)
END


--When NOT matched by target, perform an INSERT------------------------------------
SET @output += @b + 'WHEN NOT MATCHED BY TARGET THEN';
SET @output += @b + ' INSERT(' + @Column_List + ')'
SET @output += @b + ' VALUES(' + REPLACE(@Column_List, '[', '[Source].[') + ')'


--When NOT matched by source, DELETE the row as required
IF @delete_if_not_matched=1
BEGIN
 SET @output += @b + 'WHEN NOT MATCHED BY SOURCE THEN '
 SET @output += @b + ' DELETE;'
END
ELSE
BEGIN
 SET @output += ';'
END;
SET @output += @b


--Display the number of affected rows to the user, or report if an error occurred---
IF @include_rowsaffected = 1
BEGIN
 SET @output += @b + 'DECLARE @mergeError int'
 SET @output += @b + ' , @mergeCount int'
 SET @output += @b + 'SELECT @mergeError = @@ERROR, @mergeCount = @@ROWCOUNT'
 SET @output += @b + 'IF @mergeError != 0'
 SET @output += @b + ' BEGIN'
 SET @output += @b + ' PRINT ''ERROR OCCURRED IN MERGE FOR ' + @Target_Table_For_Output + '. Rows affected: '' + CAST(@mergeCount AS VARCHAR(100)); -- SQL should always return zero rows affected';
 SET @output += @b + ' END'
 SET @output += @b + 'ELSE'
 SET @output += @b + ' BEGIN'
 SET @output += @b + ' PRINT ''' + @Target_Table_For_Output + ' rows affected by MERGE: '' + CAST(@mergeCount AS VARCHAR(100));';
 SET @output += @b + ' END'
 SET @output += @b + ISNULL(@batch_separator, '')
 SET @output += @b + @b
END

--Re-enable the temporarily disabled constraints-------------------------------------
IF @disable_constraints = 1 AND @ignore_disable_constraints = 0
BEGIN
	SET @output += @output_enable_constraints
	SET @output += @b + ISNULL(@batch_separator, '')
	SET @output += @b
END


--Switch-off identity inserting------------------------------------------------------
IF (LEN(@IDN) <> 0)
 BEGIN
 SET @output += @b
 SET @output += @b +'SET IDENTITY_INSERT ' + @Target_Table_For_Output + ' OFF'

 END

IF (@include_rowsaffected = 1)
BEGIN
 SET @output += @b
 SET @output +=      'SET NOCOUNT OFF'
 SET @output += @b + ISNULL(@batch_separator, '')
 SET @output += @b
END

SET @output += @b + ''
SET @output += @b + ''

IF @results_to_text = 1
BEGIN
	--output the statement to the Grid/Messages tab
	SELECT @output;
END
ELSE IF @results_to_text = 0
BEGIN
	--output the statement as xml (to overcome SSMS 4000/8000 char limitation)
	SELECT [processing-instruction(x)]=@output FOR XML PATH(''),TYPE;
	PRINT 'MERGE statement has been wrapped in an XML fragment and output successfully.'
	PRINT 'Ensure you have Results to Grid enabled and then click the hyperlink to copy the statement within the fragment.'
	PRINT ''
	PRINT 'If you would prefer to have results output directly (without XML) specify @results_to_text = 1, however please'
	PRINT 'note that the results may be truncated by your SQL client to 4000 nchars.'
END
ELSE
BEGIN
	PRINT 'MERGE statement generated successfully (refer to @output OUTPUT parameter for generated T-SQL).'
END

SET NOCOUNT OFF
RETURN 0 --Success. We are done!
END

GO

PRINT 'Created the procedure'
GO


--Mark the proc as a system object to allow it to be called transparently from other databases
EXEC sp_MS_marksystemobject sp_generate_merge
GO

PRINT 'Granting EXECUTE permission on sp_generate_merge to all users'
GRANT EXEC ON sp_generate_merge TO public

SET NOCOUNT OFF
GO

PRINT 'Done'

#>