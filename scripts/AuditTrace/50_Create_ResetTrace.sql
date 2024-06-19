USE [master]
GO

/****** Object:  StoredProcedure [dbo].[ResetTrace]    Script Date: 10/26/2017 8:18:00 AM ******/
IF EXISTS(SELECT 1 FROM sys.procedures WHERE name = 'ResetTrace')
BEGIN
	DROP PROCEDURE [dbo].[ResetTrace]
END
GO

/****** Object:  StoredProcedure [dbo].[ResetTrace]    Script Date: 10/26/2017 8:18:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[ResetTrace] 
AS
--========================================================================================================
-- Description: Store procedure for setting trace filters and creating a SQL profiler trace.
-- Version: 2.1
-- Author: Siva Kasina & Shamile Fiaz
-- Version History:
-- 	v1.0 - Base version
-- 	v2.0 - Re-wrote filters to only include specific columns and client tools under filter criteria
-- 	v2.1 - Added SQLAgent and other client tools under application filters 
--	v2.2 - 20210727 - Commented the filter for .Net SqlClient Data Provider under app filters
--========================================================================================================

DECLARE @traceid INT, @maxsize BIGINT, @onoff BIT, @iReturn INT, @sTraceFile NVARCHAR(256);

DECLARE c4 CURSOR fast_forward LOCAL FOR 
	--SELECT traceid FROM :: fn_trace_getinfo(DEFAULT) WHERE PROPERTY = 5 AND VALUE = 1 
	--AND traceid NOT IN (
	--	SELECT traceid 
	--	FROM :: fn_trace_getinfo(DEFAULT) 
	--	WHERE PROPERTY = 1 AND VALUE = 1);
	SELECT id AS traceid
	FROM sys.traces 
	WHERE is_default = 0
	AND path LIKE 'M:\MSSQL\Traces%'
OPEN c4;

FETCH NEXT FROM c4 INTO @traceid;
WHILE @@fetch_status = 0 
BEGIN
	PRINT 'Stopping and deleting trace number ' + CONVERT(VARCHAR(4),@traceid);
	EXECUTE @iReturn = sp_trace_setstatus @traceid, 0;
	IF @iReturn <> 0
	BEGIN
		RAISERROR('Unexpected return code from sp_trace_setstatus when stopping trace: %d',16,1,@iReturn);
		RETURN;
	END;
	EXECUTE @iReturn = sp_trace_setstatus @traceid, 2;
	IF @iReturn <> 0
	BEGIN
		RAISERROR('Unexpected return code from sp_trace_setstatus when deleting trace: %d',16,1,@iReturn);
		RETURN;
	END;
	FETCH NEXT FROM c4 INTO @traceid;
END;

CLOSE c4;
DEALLOCATE c4;

SELECT @sTraceFile = CAST(value as NVARCHAR(250)) FROM sys.extended_properties WHERE name = 'TraceLocation';
IF @sTraceFile = '' OR @sTraceFile IS NULL
BEGIN
	RAISERROR('The TraceLocation extended property does not exist or is blank.',16,1);
	RETURN;
END;

IF RIGHT(@sTraceFile,1) <> '\'
	SET @sTraceFile = @sTraceFile + '\';

SET @sTraceFile = @sTraceFile + REPLACE(@@servername,'\','-') + '_' + REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR(20),GETDATE(),120),'-',''),' ',''),':','');

PRINT 'Starting trace to file: ' + @sTraceFile;

SET @maxsize = 100;
SET @onoff = 1;
EXECUTE @iReturn = sp_trace_create @traceid OUTPUT, 2, @sTraceFile, @maxsize, NULL;
--exec @iReturn = sp_trace_create @traceid output, 1, null, @maxsize, null
IF @iReturn <> 0
BEGIN
	RAISERROR('Unexpected return code from sp_trace_create: %d',16,1,@iReturn);
	RETURN;
END;
-- Events
EXECUTE sp_trace_setevent @traceid, 11, 1, @onoff; --TextData
EXECUTE sp_trace_setevent @traceid, 11, 8, @onoff; --HostName
EXECUTE sp_trace_setevent @traceid, 11, 10, @onoff; --ApplicationName
EXECUTE sp_trace_setevent @traceid, 11, 11, @onoff; --LoginName
EXECUTE sp_trace_setevent @traceid, 11, 14, @onoff; --StartTime
EXECUTE sp_trace_setevent @traceid, 11, 34, @onoff; --ObjectName
EXECUTE sp_trace_setevent @traceid, 11, 35, @onoff; --DatabaseName
EXECUTE sp_trace_setevent @traceid, 13, 1, @onoff; --TextData
EXECUTE sp_trace_setevent @traceid, 13, 8, @onoff; --HostName
EXECUTE sp_trace_setevent @traceid, 13, 10, @onoff; --ApplicationName
EXECUTE sp_trace_setevent @traceid, 13, 11, @onoff; --LoginName
EXECUTE sp_trace_setevent @traceid, 13, 14, @onoff; --StartTime
EXECUTE sp_trace_setevent @traceid, 13, 34, @onoff; --ObjectName
EXECUTE sp_trace_setevent @traceid, 13, 35, @onoff; --DatabaseName
EXECUTE sp_trace_setevent @traceid, 20, 8, @onoff; --HostName
EXECUTE sp_trace_setevent @traceid, 20, 10, @onoff; --ApplicationName
EXECUTE sp_trace_setevent @traceid, 20, 11, @onoff; --LoginName
EXECUTE sp_trace_setevent @traceid, 20, 14, @onoff; --StartTime
EXECUTE sp_trace_setevent @traceid, 20, 34, @onoff; --ObjectName
EXECUTE sp_trace_setevent @traceid, 20, 35, @onoff; --DatabaseName

--Application
EXECUTE sp_trace_setfilter @traceid, 10, 1, 6, N'Microsoft SQL Server Management Studio%';
EXECUTE sp_trace_setfilter @traceid, 10, 1, 6, N'SQLAgent - TSQL JobStep%';
EXECUTE sp_trace_setfilter @traceid, 10, 1, 0, N'SQLCMD';
EXECUTE sp_trace_setfilter @traceid, 10, 1, 0, N'SQL Management';
--EXECUTE sp_trace_setfilter @traceid, 10, 1, 6, N'.Net SqlClient Data Provider%';
EXECUTE sp_trace_setfilter @traceid, 10, 1, 0, N'azdata-Query';

--SQL Management

--Logins

--Text

EXECUTE @iReturn = sp_trace_setstatus @traceid, 1;
IF @iReturn <> 0
BEGIN
	RAISERROR('Unexpected return code from sp_trace_setstatus when starting trace: %d',16,1,@iReturn);
	RETURN;
END;
--SELECT * FROM sys.traces 


GO

EXEC sp_procoption N'[dbo].[ResetTrace]', 'startup', '1'
GO


EXEC master.dbo.resettrace