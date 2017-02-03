SET NOCOUNT ON
GO

--Determine the columns that are intended to be changed, store them in a list:
select distinct 
	objectId = si.object_id,
	TableName = t.name,
	ColumnName = sc.name,
	isNullable = sc.is_nullable,
	NeedsBigInt = 1,
	printDrop = 0,
	printAlter = 0,
	PrintCreate = 0
into
	#tmpTargetObjects
from SYS.INDEXES si
inner join sys.columns sc
	on si.object_id = sc.object_id
inner join sys.tables t
	on t.object_id = si.object_id
	where ( sc.name in ('PACKAGE_ID','CHARGE_ID','ADVICE_ID',
					'INVOICE_ID','BUNDLE_ID','LINE_ITEM_ID',
					'ADDRESS_ID','SHIPPER_ID','CONSIGNEE_ID',
					'ADDRESS_CORRECTION_ID','SHIPPER_ADDR_ID','INCORRECT_ADDR_ID',
					'CORRECT_ADDR_ID','COMMENT_ID','DIMENSION_ID',
					'SHIPPER_FD_ID','REMITTANCE_ID','DESTINATION_ID',
					'ORIGIN_ID','EXCEPTION','RESOLVED_GL_CODE',
					'PK_RESOLVED_GL_CODE','TARS_EXPORT_INVOICE', 'INCORRECT_ADDR_ID',
					'CORRECT_ADDR_ID', 'SHIPPER_ADDR_ID', 'ORIGINAL_ADVICE_ID',
					'ADJUSTMENT_ADVICE_ID')
			and t.name in ('ACCOUNT','ACCOUNTING_FACT_TABLE','ACTION',
					'ACTION_CODE','ADDRESS','ADDRESS_CORRECTION',
					'ADVICE','AUDIT_SAVINGS','AUDIT_SAVINGS_PACKAGE','AUDIT_SAVINGS_STATUS',
					'AUDIT_SAVINGS_TOTAL','BILL_DESCRIPTION','BILL_IO_CODE','BUNDLE','CHARGE',
					'CHARGE_CODE','CHARGE_CODE_DISCOUNT','CHARGE_CODE_EXCLUDE','CHARGE_CODE_FREIGHT',
					'CHARGE_EXTRACT_SESSION','CHARGE_FACT_TABLE','CHARGE_GL_XREF','CHARGE_HIERARCHY',
					'COMMENT','COMMENT_CODE','CUSTOMER_REFERENCE_NUMBER','DIMENSION','EXCEPTION','EXPORT_GL_INVOICE',
					'EXPORT_PAY_INVOICE','GL_EXTRACT_SESSION','INVOICE','INVOICE_EXTRA_TABLE','IO_CODE_LOOKUP',
					'LINE_ITEM','MISCELLANEOUS_CLAIM','PACKAGE','PACKAGE_COMMENT','PACKAGE_EXTRACT_SESSION','PACKAGE_FACT_TABLE',
					'PACKAGE_GL_XREF','PACKAGE_TYPE','PICKUP_REFERENCE_NUMBER','REJECT_CODE','REMITTANCE','REMITTANCE_CLAIM_CODE',
					'REMITTANCE_HISTORY','RESOLVED_GL_CODE','SERVICE','SHIPPER','SUB_SERVICE','ZONE_HIERARCHY'))
			--OR sc.name in  ('PACKAGE_ID','CHARGE_ID','ADVICE_ID',
			--		'INVOICE_ID','BUNDLE_ID','LINE_ITEM_ID',
			--		'ADDRESS_ID','SHIPPER_ID','CONSIGNEE_ID',
			--		'ADDRESS_CORRECTION_ID','SHIPPER_ADDR_ID','INCORRECT_ADDR_ID',
			--		'CORRECT_ADDR_ID','COMMENT_ID','DIMENSION_ID',
			--		'SHIPPER_FD_ID','REMITTANCE_ID','DESTINATION_ID',
			--		'ORIGIN_ID','EXCEPTION','RESOLVED_GL_CODE',
			--		'PK_RESOLVED_GL_CODE','TARS_EXPORT_INVOICE', 'INCORRECT_ADDR_ID',
			--		'CORRECT_ADDR_ID', 'SHIPPER_ADDR_ID', 'ORIGINAL_ADVICE_ID',
			--		'ADJUSTMENT_ADVICE_ID')

GROUP BY t.name, sc.name, si.object_id, sc.is_nullable
ORDER BY t.name

--Determine the FOREIGN KEYS to modify

SELECT  obj.name AS constraintname,
    tab1.name AS thistable,
    col1.name AS thiscolumn,
    tab2.name AS referencedtable,
    col2.name AS referencedcolumn,
	printDrop = 0,
	printAlter = 0,
	printCreate = 0,
	isnullable = col1.is_nullable,
	NeedsBigInt = 0
into #tmpForeignKey
FROM sys.foreign_key_columns fkc
INNER JOIN sys.objects obj
    ON obj.object_id = fkc.constraint_object_id
INNER JOIN sys.tables tab1
    ON tab1.object_id = fkc.parent_object_id
INNER JOIN sys.columns col1
    ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
INNER JOIN sys.tables tab2
    ON tab2.object_id = fkc.referenced_object_id
INNER JOIN sys.columns col2
    ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id
WHERE
	col2.name in (select distinct ColumnName from #tmpTargetObjects)


--Determine what columns need to be modified to make FK datatypes match
UPDATE
	#tmpForeignKey
SET
	NeedsBigInt = 1
WHERE
	referencedcolumn in (select columnname from #tmpTargetObjects)

--Determine what DEFAULT CONSTRAINTS exist that need to be modified.
SELECT
	default_constraints.name as ConstraintName,
	tables.name as TableName,
	all_columns.name as ColumnName,
	default_constraints.definition as DefaultValue,
	printDrop = 0,
	printAlter = 0,
	printCreate = 0
INTO
	#tmpConstraints
FROM 
    sys.all_columns
INNER JOIN
    sys.tables
        ON all_columns.object_id = tables.object_id
INNER JOIN 
    sys.schemas
        ON tables.schema_id = schemas.schema_id
INNER JOIN
    sys.default_constraints
        ON all_columns.default_object_id = default_constraints.object_id
WHERE sys.all_columns.name IN (select distinct ColumnName from #tmpTargetObjects)
	--OR sys.all_columns.name in (select distinct thiscolumn from #tmpForeignKey)

--Determine which primary keys need to be modified here.
--This will likely be a duplicate of #tmpTargetObjects, but we're being sure we're GOing to hit the right things.
SELECT 
	ST.Schema_id 
	,ST.Object_id 
	,SI.Index_id 
	,SCH.Name as schemaname
	,ST.Name as tablename
	,SI.Name as pkname
	,SI.is_primary_key 
	,SI.Type,
	NeedsBigInt = 0,
	printDrop = 0,
	printAlter = 0,
	printCreate = 0
INTO
	#tmpPrimaryKeys
FROM SYS.INDEXES SI 
JOIN SYS.TABLES  ST 
	ON SI.Object_ID = ST.Object_ID 
JOIN SYS.SCHEMAS SCH 
	ON SCH.schema_id = ST.schema_id 
WHERE SCH.Name = 'dbo'
	AND (ST.name IN (select distinct TableName from #tmpTargetObjects) 
		OR ST.name in (select distinct thistable from #tmpForeignKey))
    AND SI.is_primary_key = 1

--Determine INDEXES affected by the bigint change, get them ready to GO.
SELECT 
	 ST.Schema_id 
	,ST.Object_id 
	,SI.Index_id 
	,SCH.Name as schemaname
	,ST.Name as tablename
	,SI.Name as indexname
	,SI.is_primary_key 
	,SI.Type,
	printDrop = 0,
	printAlter = 0,
	printCreate = 0
INTO
	#tmpIndex
FROM SYS.INDEXES SI 
JOIN SYS.TABLES  ST 
	ON SI.Object_ID = ST.Object_ID 
JOIN SYS.SCHEMAS SCH 
	ON SCH.schema_id = ST.schema_id 
WHERE SCH.Name = 'dbo'
	AND (ST.name IN (select TableName from #tmpTargetObjects) 
		OR ST.name in (select distinct thistable from #tmpForeignKey))
	AND SI.is_primary_key = 0
	AND SI.is_unique = 0
	AND SI.is_unique_constraint = 0
	AND SI.Type in (1,2,3) --Makes sure we only get indexes, not constraints or primary keys.

--Modify the tables so we can store the generated scripts

alter table #tmpForeignKey
add Drop_Sql varchar(5000), Create_Sql varchar(5000)

alter table #tmpConstraints
add Drop_SQL varchar(5000), Create_Sql varchar(5000)

alter table #tmpPrimaryKeys
add Drop_SQL varchar(5000), Create_Sql varchar(5000)

alter table #tmpIndex
add Drop_SQL varchar(5000), Create_Sql varchar(5000)

--Generate some variables to work on the table information.

declare @tablename varchar(100),
		@columnname varchar(200),
		@constraintname varchar(300),
		@printsql varchar(2500),
		@defaultValue varchar(1000),
		@referencetable varchar(500),
		@referencedcolumn varchar(500),
		@CreateSql varchar(max),
		@WithSql varchar(max),
		@IndexColsSql varchar(max),
		@WhereSql varchar(max),
		@IncludeSql varchar(max)

--Generate the scripts for Foreign Keys.
WHILE EXISTS(Select * from #tmpForeignKey where DROP_SQL is null and CREATE_SQL is null)
BEGIN
	SELECT top 1 @tablename = thistable,
				@columnname = thiscolumn,
				@constraintname = constraintname,
				@referencetable = referencedtable,
				@referencedcolumn = referencedcolumn
	from #tmpForeignKey
	WHERE DROP_SQL is null and CREATE_SQL is null

	update #tmpForeignKey 
	set
		drop_sql = 'ALTER TABLE [dbo].[' + @tablename + '] DROP CONSTRAINT [' + @constraintname + ']',
		create_sql = 'ALTER TABLE [dbo].[' + @tablename + '] ADD CONSTRAINT [' + @constraintname + '] FOREIGN KEY ([' + @columnname + ']) REFERENCES [dbo].[' + @referencetable + '] ([' + @referencedcolumn + '])'
	where 
		thistable = @tablename 
		and thiscolumn = @columnname 
		and referencedtable = @referencetable
		and referencedcolumn = @referencedcolumn 
		and @constraintname = constraintname
END

--Generate scripts for Primary Keys



while EXISTS(Select * from #tmpPrimaryKeys where DROP_SQL is null and CREATE_SQL is null)
BEGIN
SELECT top 1 @tablename = tablename,
				@constraintname = pkname
	from #tmpPrimaryKeys
	WHERE DROP_SQL is null and CREATE_SQL is null

	SELECT @CreateSQL = 'ALTER TABLE [dbo].' + @tablename + ' ADD  CONSTRAINT [' + @constraintname + '] PRIMARY KEY ' + SI.type_desc ,
			@IndexColsSQL =  ( SELECT SC.Name + ' '	
									+ CASE SIC.is_descending_key 
										WHEN 0 THEN ' ASC '  
										ELSE 'DESC' 
										END +  ',' 
								FROM SYS.INDEX_COLUMNS SIC 
									JOIN SYS.COLUMNS SC 
									ON SIC.Object_ID = SC.Object_ID 
										AND SIC.Column_ID = SC.Column_ID 
								WHERE SIC.OBJECT_ID = SI.Object_ID 
									AND SIC.Index_ID  = SI.Index_ID 
									AND SIC.is_included_column = 0 
									ORDER BY SIC.Key_Ordinal 
									FOR XML PATH('') )  
					--@IncludeSQl covers what things are part of the Primary Key.
					,@IncludeSQL =  ( SELECT QUOTENAME(SC.Name) +  ',' 
								FROM SYS.INDEX_COLUMNS SIC 
								JOIN SYS.COLUMNS SC 
								ON SIC.Object_ID = SC.Object_ID 
								AND SIC.Column_ID = SC.Column_ID 
								WHERE SIC.OBJECT_ID = SI.Object_ID 
								AND SIC.Index_ID  = SI.Index_ID 
								AND SIC.is_included_column = 1 
								ORDER BY SIC.Key_Ordinal 
								FOR XML PATH('') 
								)  
					,@WhereSQL  = SI.Filter_Definition 
			FROM SYS.Indexes SI 
			JOIN SYS.FileGroups SFG 
			ON SI.Data_Space_ID =SFG.Data_Space_ID 
			WHERE Object_ID = object_id(@tablename) 
			--AND Index_ID  = object_id(@constraintname) 
			AND SI.name = @constraintname

    SELECT @IndexColsSQL = '(' + SUBSTRING(@IndexColsSQL,1,LEN(@IndexColsSQL)-1) + ')' 
	      
    IF LTRIM(RTRIM(@IncludeSQL)) <> '' 
		SELECT @IncludeSQL   = ' INCLUDE (' + SUBSTRING(@IncludeSQL,1,LEN(@IncludeSQL)-1) + ')' 
             
    IF LTRIM(RTRIM(@WhereSQL)) <> '' 
		SELECT @WhereSQL        = ' WHERE (' + @WhereSQL + ')'

	SELECT @CreateSQL = @CreateSQL  
                + @IndexColsSQL + CASE WHEN @IndexColsSQL <> '' THEN CHAR(13) ELSE '' END 
                + ISNULL(@IncludeSQL,'') + CASE WHEN @IncludeSQL <> '' THEN CHAR(13) ELSE '' END 
                + ISNULL(@WhereSQL,'') + CASE WHEN @WhereSQL <> '' THEN CHAR(13) ELSE '' END  
                + ISNULL(@WithSQL, '')

	update #tmpPrimaryKeys
	SET
		drop_sql = 'ALTER TABLE [dbo].['+ @tablename + '] DROP CONSTRAINT [' + @constraintname + ']',
		create_sql = @CreateSql
	WHERE
		tablename = @tablename
		and pkname = @constraintname
	

END

--Generate scripts for INDEXES
while EXISTS(Select * from #tmpIndex where DROP_SQL is null and CREATE_SQL is null)
BEGIN

	SELECT top 1 @tablename = tablename,
				 @constraintname = indexname
	from #tmpIndex
	WHERE DROP_SQL is null and CREATE_SQL is null

	BEGIN 
                SELECT @CreateSQL = 'CREATE ' + CASE SI.is_Unique WHEN 1 THEN ' UNIQUE ' ELSE '' END + SI.type_desc + ' INDEX ' + QUOTENAME(SI.Name) + ' ON [dbo].' + @tablename  
                      ,@IndexColsSQL =  ( SELECT SC.Name + ' '  
                                 + CASE SIC.is_descending_key 
                                   WHEN 0 THEN ' ASC '  
                                   ELSE 'DESC' 
                                   END +  ',' 
                            FROM SYS.INDEX_COLUMNS SIC 
                            JOIN SYS.COLUMNS SC 
                              ON SIC.Object_ID = SC.Object_ID 
                             AND SIC.Column_ID = SC.Column_ID 
                          WHERE SIC.OBJECT_ID = SI.Object_ID 
                            AND SIC.Index_ID  = SI.Index_ID 
                            AND SIC.is_included_column = 0 
                          ORDER BY SIC.Key_Ordinal 
                           FOR XML PATH('') 
                        )   
						--Covers what columns are part of the Index.
                        ,@IncludeSQL =  ( SELECT QUOTENAME(SC.Name) +  ',' 
                                            FROM SYS.INDEX_COLUMNS SIC 
                                            JOIN SYS.COLUMNS SC 
                                              ON SIC.Object_ID = SC.Object_ID 
                                             AND SIC.Column_ID = SC.Column_ID 
                                          WHERE SIC.OBJECT_ID = SI.Object_ID 
                                            AND SIC.Index_ID  = SI.Index_ID 
                                            AND SIC.is_included_column = 1 
                                          ORDER BY SIC.Key_Ordinal 
                                           FOR XML PATH('') 
                                        )  
                        ,@WhereSQL  = SI.Filter_Definition 
                  FROM SYS.Indexes SI 
                  JOIN SYS.FileGroups SFG 
                    ON SI.Data_Space_ID =SFG.Data_Space_ID 
                 WHERE Object_ID = object_id(@tablename) 
                   AND Si.name = @constraintname
                    
                   SELECT @IndexColsSQL = '(' + SUBSTRING(@IndexColsSQL,1,LEN(@IndexColsSQL)-1) + ')' 
                    
                   IF LTRIM(RTRIM(@IncludeSQL)) <> '' 
                        SELECT @IncludeSQL   = ' INCLUDE (' + SUBSTRING(@IncludeSQL,1,LEN(@IncludeSQL)-1) + ')' 
                 
                   IF LTRIM(RTRIM(@WhereSQL)) <> '' 
                       SELECT @WhereSQL        = ' WHERE (' + @WhereSQL + ')' 
         
        END 
        --Handle Indexes.
        
 
        SELECT @CreateSQL = @CreateSQL  
                            + @IndexColsSQL + CASE WHEN @IndexColsSQL <> '' THEN CHAR(13) ELSE '' END 
                            + ISNULL(@IncludeSQL,'') + CASE WHEN @IncludeSQL <> '' THEN CHAR(13) ELSE '' END 
                            + ISNULL(@WhereSQL,'') + CASE WHEN @WhereSQL <> '' THEN CHAR(13) ELSE '' END  
                            + ISNULL(@WithSQL, '')
	update #tmpIndex
	SET
		drop_sql = 'DROP INDEX [' + @constraintname +'] on [dbo].['+ @tablename + ']',
		create_sql = @CreateSql
	WHERE
		tablename = @tablename
		and indexname = @constraintname

END

--Script out the DEFAULT CONSTRAINTS involved.
WHILE EXISTS(SELECT * FROM #tmpConstraints where DROP_SQL is null and CREATE_SQL is null)
BEGIN

	SELECT TOP 1 
		@tablename = tablename,
		@columnname = columnname,
		@defaultValue = defaultValue,
		@constraintname = constraintname
	from #tmpConstraints
	where 
		DROP_SQL is null
		and CREATE_SQL is null

	update #tmpConstraints
	SET
		DROP_SQL = 'ALTER TABLE [dbo].[' + @tablename +'] DROP CONSTRAINT ['+ @constraintname +']',
		CREATE_SQL = 'ALTER TABLE ' + @tableName + ' add constraint ' + @constraintName + ' default ' + @defaultValue + ' for ' + @columnname 
	where 
		tablename = @tablename 
		and columnname = @columnname 
		and constraintname = @constraintname

END

--Set up some DEBUG stuff to make tracking down problems easier.
declare @DebugLine varchar(200), @CatchLine varchar(3000)
set @DebugLine =  'print ''Successfully removed: '' + '''
set @CatchLine = 'end try begin catch print ''ERROR -> '' + error_message() end catch'

--Print DROP FK script

print replicate('-', 100)
print '-- DROP FK statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''DROP FK statements'''
print 'print replicate(''-'', 100)'

--Print the FOREIGN KEY drops.
while EXISTS(Select * from #tmpForeignKey where printDrop = 0)
BEGIN

	SELECT top 1 @tablename = thistable,
				@columnname = thiscolumn,
				@constraintname = constraintname,
				@referencetable = referencedtable,
				@referencedcolumn = referencedcolumn,
				@printsql = drop_sql
	from #tmpForeignKey
	where printDrop = 0
	print 'Begin Try'
	print @printSql
	--print 'GO'
	--print @DebugLine + @constraintname + ''''
	print @CatchLine
	update #tmpForeignKey
	SET
		printDrop = 1
	WHERE
		thistable= @tablename 
		and thiscolumn= @columnname 
		and @constraintname = constraintname
		AND @referencetable = referencedtable
		and @referencedcolumn = referencedcolumn
END

print replicate('-', 100)
print '-- Drop PK statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''DROP PK statements'''
print 'print replicate(''-'', 100)'

--Print the PRIMARY KEY drops
while EXISTS(Select * from #tmpPrimaryKeys where printDrop = 0)
BEGIN
	SELECT top 1 @tablename = tablename,
				@constraintname = pkName,
				@printsql = drop_sql
	from #tmpPrimaryKeys
	where printDrop = 0
	print 'BEGIN TRY'
	print @printSql
	--print 'GO'
	print @CatchLine
	update #tmpPrimaryKeys
	SET
		printDrop = 1
	WHERE
		tablename = @tablename 
		and pkName = @constraintname
END

print replicate('-', 100)
print '-- DROP INDEX statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''DROP INDEX statements'''
print 'print replicate(''-'', 100)'

--Print the INDEX drops
while EXISTS(SELECT * FROM #TMPINDEX WHERE printDROP = 0)
BEGIN

	SELECT top 1 @tablename = tablename,
				@constraintname = indexname,
				@printsql = drop_sql
	from #tmpIndex
	where printDrop = 0
	
	print 'BEGIN TRY'
	print @printSql
	--print 'GO'
	print @CatchLine

	update #tmpIndex
	SET
		printDrop = 1
	WHERE
		tablename = @tablename 
		and indexname = @constraintname

END

--Print the DEFAULT CONSTRAINT drops
print replicate('-', 100)
print '-- DROP DEFAULT CONSTRAINTS statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''DROP DEFAULT CONSTRAINT statements'''
print 'print replicate(''-'', 100)'

while EXISTS(Select * from #tmpConstraints where printDrop = 0)
BEGIN

	SELECT top 1 @tablename = tablename,
				@columnname = columnname,
				@constraintname = constraintname,
				@printsql = drop_sql
	from #tmpConstraints
	where printDrop = 0

	print 'BEGIN TRY'
	print @printSql
	--print 'GO'
	--print @DebugLine + @constraintname + ''''
	print @CatchLine

	update #tmpConstraints
	SET
		printDrop = 1
	WHERE
		tablename = @tablename 
		and columnname = @columnname 
		and @constraintname = constraintname
END

print replicate('-', 100)
print '-- Alter Columns based on the target objects'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''Alter columns based on the target objects'''
print 'print replicate(''-'', 100)'

--Create Alter statements for the columns getting the BigInt change only
declare @isNullable int

select * into #tmpModifyColumns FROM (select tobj.tablename as tablename, tobj.columnname as columnname, tobj.isNullable as isNullable, tobj.printAlter as printAlter, tobj.needsBigInt as needsBigInt
		from #tmpTargetObjects tobj
		where needsBigInt = 1

		UNION

		select tfk.thistable as tablename, tfk.thiscolumn as columnname, tfk.isNullable as isNullable, tfk.printAlter as printAlter, tfk.needsBigInt as needsBigInt
		from #tmpForeignKey tfk
		where tfk.needsBigInt = 1) as tmp


set @DebugLine = 'print ''Successfully Altered: '' + '''

while EXISTS(Select * from #tmpModifyColumns where printAlter = 0)
BEGIN
	SELECT TOP 1
		@tablename = tablename,
		@columnname = columnname,
		@isNullable = isNullable
	from #tmpModifyColumns
	where printAlter = 0
	and needsbigint = 1
	print 'BEGIN TRY'
	print 'ALTER TABLE ' + @tablename + ' ALTER COLUMN ' + @columnname + ' BIGINT ' + CASE WHEN @isNullable = 1 then ' ' ELSE 'NOT NULL' END 
	print @DebugLine + @tablename + '.' + @columnname + ''''
	print @CatchLine

	update #tmpModifyColumns
	set
		printAlter = 1
	WHERE
		tablename = @tablename
		AND	columnname = @columnname
end

set @DebugLine = 'print ''Successfully added: '' + '''
--PRINT CREATE Default Constraints

print replicate('-', 100)
print '-- Create Default Constraint statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''Create Default constraint statements'''
print 'print replicate(''-'', 100)'
while EXISTS(Select * from #tmpConstraints where printCreate = 0)
BEGIN

	SELECT top 1 @tablename = tablename,
				@columnname = columnname,
				@constraintname = constraintname,
				@printsql = create_sql
	from #tmpConstraints
	where printCreate = 0

	print 'BEGIN TRY'
	print @printSql
	--print 'GO'
	--print @DebugLine + @constraintname + ''''
	print @CatchLine

	update #tmpConstraints
	SET
		printCreate = 1
	WHERE
		tablename = @tablename 
		and columnname = @columnname 
		and @constraintname = constraintname
END


print replicate('-', 100)
print '-- Create Index statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''Create Index statements'''
print 'print replicate(''-'', 100)'

--PRINT CREATE INDEX
while EXISTS(SELECT * from #tmpIndex where printCreate = 0)
BEGIN
select top 1 
		@tablename = tableName,
		@constraintname = indexname,
		@printSql = create_sql
	from #tmpIndex
	where
		printCreate = 0

	print 'BEGIN TRY'
	print @printsql
	--print 'GO'
	--print @DebugLine + @constraintname + ''''
	print @CatchLine

	update #tmpIndex
	SET
		printCreate = 1
	WHERE
		tablename = @tablename
		AND indexname = @constraintName
END

print replicate('-', 100)
print '-- Create PK statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''Create PK statements'''
print 'print replicate(''-'', 100)'

--PRINT CREATE PK
while EXISTS (SELECT * FROM #tmpPrimaryKeys where printCreate = 0)
BEGIN
	select top 1 
		@tablename = tableName,
		@constraintname = pkName,
		@printSql = create_sql
	from #tmpPrimaryKeys
	where
		printCreate = 0

	print 'BEGIN TRY'
	print @printsql
	--print 'GO'
	--print @DebugLine + @constraintname + ''''
	print @CatchLine

	update #tmpPrimaryKeys
	SET
		printCreate = 1
	WHERE
		tablename = @tablename
		AND pkname = @constraintName

END

--Print CREATE FK SCRIPT

print replicate('-', 100)
print '-- Create FK statements'
print replicate('-', 100)

print 'print replicate(''-'', 100)'
print 'print replicate(''-'', 2) + ''Create FK statements'''
print 'print replicate(''-'', 100)'

while EXISTS(Select * from #tmpForeignKey where printCreate = 0)
BEGIN

	SELECT top 1 @tablename = thistable,
				@columnname = thiscolumn,
				@constraintname = constraintname,
				@printsql = create_sql
	from #tmpForeignKey
	where printCreate = 0
	print 'BEGIN TRY'
	print @printSql
	--print 'GO'
	--print @DebugLine + @constraintname + ''''
	print @CatchLine

	update #tmpForeignKey
	SET
		printCreate = 1
	WHERE
		thistable = @tablename 
		and thiscolumn = @columnname 
		and @constraintname = constraintname
END

--Drop the SP here