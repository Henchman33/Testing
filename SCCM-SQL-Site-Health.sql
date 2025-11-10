-- Comprehensive SCCM database health monitoring script with error types and remediation guidance for each query:
-- SCCM Database Health and Error Monitoring Queries
-- sql

-- Set the database context
USE CM_P01;
GO

--1. Database Corruption Check
--sql

-- Error Type: Database Corruption
-- Description: Checks for physical and logical database corruption
DBCC CHECKDB WITH NO_INFOMSGS, ALL_ERRORMSGS;

--Remediation:

 --   Immediate Action: If errors are found, restore from backup immediately
--
 --   If no recent backup: Use DBCC CHECKDB WITH REPAIR_ALLOW_DATA_LOSS (last resort)

 --   Prevention: Regular maintenance plans, consistent backups, monitor disk health

--2. SQL Server Error Log
--sql

-- Error Type: SQL Server Errors
-- Description: Recent SQL Server errors affecting SCCM
SELECT 
    [LogDate],
    [ProcessInfo],
    [Text] AS ErrorMessage
FROM 
    sys.fn_dblog(NULL, NULL)
WHERE 
    [Text] LIKE '%error%'
    AND [LogDate] >= DATEADD(DAY, -1, GETDATE())
ORDER BY 
    [LogDate] DESC;

--Remediation:

 --   17xx errors: Hardware/memory issues - check hardware, run diagnostics

 --   8xx errors: Page corruption - restore from backup

 --   2xxx errors: Syntax/connection issues - check application logs

  --  General: Review SQL Server error log for patterns

--3. Failed SCCM Component Status
sql

-- Error Type: Component Failures
-- Description: SCCM components with errors
SELECT 
    [ComponentName],
    [SiteCode],
    [MachineName],
    [MessageID],
    [MessageType],
    [MessageTime],
    [MessageText]
FROM 
    dbo.vSMS_ComponentSummarizer
WHERE 
    [MessageType] IN (2, 3) -- Warning and Error messages
    AND [MessageTime] >= DATEADD(DAY, -1, GETDATE())
ORDER BY 
    [MessageTime] DESC;

Remediation:

    Specific component failures: Restart the component via SCCM console

    Multiple components failing: Check site server services, disk space, permissions

    Persistent errors: Review component logs, check dependencies

4. Site System Status Errors
sql

-- Error Type: Site System Communication
-- Description: Site systems with connectivity/issues
SELECT 
    [SiteCode],
    [SiteSystem],
    [Role],
    [Status],
    [LastStatusTime]
FROM 
    dbo.vSMS_SiteSystemSummarizer
WHERE 
    [Status] <> 1 -- Not OK status
ORDER BY 
    [LastStatusTime] DESC;

Remediation:

    Network connectivity: Verify DNS, network connectivity, firewall ports

    Permissions: Check site system computer account permissions

    Services: Verify required services are running on site systems

5. Replication Link Status
sql

-- Error Type: Database Replication
-- Description: Checks for replication issues between sites
SELECT 
    [SiteCode],
    [LinkedSiteCode],
    [LinkType],
    [LinkStatus],
    [LastReplicationTime],
    [LastReplicationStatus]
FROM 
    dbo.ReplicationData
WHERE 
    [LinkStatus] <> 1 -- Replication issues
    OR [LastReplicationStatus] <> 1;

--Remediation:

  --  Broken replication: Use Replication Link Analyzer in SCCM

 --   Network issues: Check firewalls, certificates, SQL Server connectivity

   -- Data conflicts: Monitor replication groups for conflicts-->

--6. Failed SCCM Jobs
--sql

-- Error Type: Background Job Failures
-- Description: SCCM background jobs that have failed
SELECT 
    [JobID],
    [JobName],
    [LastRunStatus],
    [LastRunTime],
    [LastErrorCode]
FROM 
    dbo.vSMS_Job
WHERE 
    [LastRunStatus] <> 1 -- Failed jobs
    AND [LastRunTime] >= DATEADD(DAY, -7, GETDATE())
ORDER BY 
    [LastRunTime] DESC;

--Remediation:

   -- Specific job failures: Check job history, dependencies

  --  Maintenance jobs: Verify maintenance windows, resource availability

  --  Recurring failures: Review job parameters, target resources

--7. Disk Space Monitoring
--

-- Error Type: Storage Issues
-- Description: Database and disk space utilization
EXEC sp_spaceused;

-- Additional disk space check
SELECT 
    name AS FileName,
    size/128.0 AS CurrentSizeMB,
    size/128.0 - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0 AS FreeSpaceMB,
    growth AS GrowthSetting,
    CASE 
        WHEN growth = 0 THEN 'No growth'
        ELSE 'Growing'
    END AS GrowthStatus
FROM 
    sys.database_files;

--Remediation:

 --   Low disk space: Clean up old data, expand disks, move files

 --   Database file growth: Monitor autogrowth settings, pre-allocate space

 --   TempDB issues: Check TempDB configuration and growth

--8. Blocking Processes
--sql

-- Error Type: Performance Blocking
-- Description: Identifies blocking processes causing timeouts
SELECT 
    blocking_session_id AS BlockingSPID,
    wait_duration_ms AS WaitTimeMS,
    session_id AS BlockedSPID,
    wait_type,
    resource_description,
    (SELECT text FROM sys.dm_exec_sql_text(sql_handle)) AS SQLText
FROM 
    sys.dm_os_waiting_tasks
WHERE 
    blocking_session_id IS NOT NULL;

--Remediation:

 --   Short-term: Identify and kill blocking processes if safe

 --   Long-term: Optimize queries, add indexes, review transaction handling

 --   Application: Check for long-running operations in SCCM console

--9. Index Fragmentation
---ql

-- Error Type: Performance Degradation
-- Description: Highly fragmented indexes affecting performance
SELECT 
    OBJECT_NAME(ind.OBJECT_ID) AS TableName,
    ind.name AS IndexName,
    indexstats.index_type_desc AS IndexType,
    indexstats.avg_fragmentation_in_percent AS FragmentationPercent,
    indexstats.page_count AS PageCount
FROM 
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') indexstats
INNER JOIN 
    sys.indexes ind ON ind.object_id = indexstats.object_id AND ind.index_id = indexstats.index_id
WHERE 
    indexstats.avg_fragmentation_in_percent > 30
    AND indexstats.page_count > 1000
ORDER BY 
    indexstats.avg_fragmentation_in_percent DESC;

--Remediation:

 --   30-50% fragmentation: ALTER INDEX REORGANIZE

 --   >50% fragmentation: ALTER INDEX REBUILD

 --   Maintenance: Implement regular index maintenance jobs

--10. Long-Running Queries
--sql

-- Error Type: Query Performance
-- Description: Queries running longer than 30 seconds
SELECT 
    session_id,
    start_time,
    status,
    command,
    wait_type,
    wait_time,
    cpu_time,
    total_elapsed_time,
    reads,
    writes,
    logical_reads,
    SUBSTRING(text, 
        CASE WHEN statement_start_offset = 0 THEN 1 ELSE statement_start_offset/2 + 1 END,
        CASE WHEN statement_end_offset = -1 THEN DATALENGTH(text) ELSE statement_end_offset/2 END
    ) AS query_text
FROM 
    sys.dm_exec_requests
CROSS APPLY 
    sys.dm_exec_sql_text(sql_handle)
WHERE 
    total_elapsed_time > 30000 -- 30 seconds
    AND session_id > 50 -- Exclude system processes
ORDER BY 
    total_elapsed_time DESC;

--Remediation:

  --  Immediate: Identify and optimize problematic queries

 --   Indexing: Add missing indexes based on query patterns

 --   Statistics: Update statistics regularly

 --   Hardware: Consider resource upgrades if consistently slow

--11. Client Health Issues
--sql

-- Error Type: Client Communication
-- Description: Clients with health evaluation failures
SELECT 
    [ResourceID],
    [Netbios_Name0] AS ComputerName,
    [ClientVersion],
    [LastHealthEvaluation],
    [LastHealthEvaluationResult],
    [LastHealthEvaluationMessage]
FROM 
    dbo.v_ClientHealthState
WHERE 
    [LastHealthEvaluationResult] <> 1 -- Unhealthy clients
    AND [LastHealthEvaluation] >= DATEADD(DAY, -7, GETDATE())
ORDER BY 
    [LastHealthEvaluation] DESC;

--Remediation:

  --  Client repairs: Use Client Center or CCMClean.exe

 --   Communication: Check network connectivity, firewall ports

 --   Reinstallation: Reinstall client if persistent issues

 --   Policy: Verify client can receive policies

--12. Content Distribution Failures
--sql

-- Error Type: Content Distribution
-- Description: Failed package/content distributions
SELECT 
    [PackageID],
    [Name] AS PackageName,
    [LastStatus],
    [LastRunTime],
    [LastErrorCode],
    [DistributionPoint]
FROM 
    dbo.v_PackageStatus
WHERE 
    [LastStatus] <> 0 -- Failed distributions
    AND [LastRunTime] >= DATEADD(DAY, -7, GETDATE())
ORDER BY 
    [LastRunTime] DESC;

--Remediation:

--    Distribution points: Check DP health, disk space, permissions

 --   Network: Verify network connectivity to DPs

 --   Content: Redistribute content, validate source files

  --  Permissions: Check distribution point permissions

--13. Software Update Synchronization Issues
--

-- Error Type: WSUS Synchronization
-- Description: Software update point synchronization failures
SELECT 
    [SyncError],
    [LastSyncTime],
    [LastSyncState],
    [WSUSServer]
FROM 
    dbo.v_UpdateSyncStatus
WHERE 
    [SyncError] IS NOT NULL
    OR [LastSyncState] <> 1
ORDER BY 
    [LastSyncTime] DESC;

--Remediation:

  --  WSUS health: Run WSUS cleanup, reset synchronization

 --   Connectivity: Verify internet access, proxy settings

 --   Certificates: Check SSL certificates for WSUS

  --  Services: Restart WSUS and related services

--14. Collection Evaluation Issues
--sql

-- Error Type: Collection Management
-- Description: Collection evaluation failures
SELECT 
    [CollectionID],
    [Name] AS CollectionName,
    [LastMemberChangeTime],
    [LastRefreshTime],
    [RefreshType],
    [ErrorCode]
FROM 
    dbo.v_Collections
WHERE 
    [ErrorCode] IS NOT NULL
    AND [LastRefreshTime] >= DATEADD(DAY, -7, GETDATE())
ORDER BY 
    [LastRefreshTime] DESC;

--Remediation:

  --  Query-based collections: Validate collection query syntax

 --   Incremental updates: Check if incremental updates are causing issues

  --  Performance: Optimize collection queries, schedule during off-hours

  --  Permissions: Verify account has proper permissions

--15. Inventory Processing Errors
--sql

-- Error Type: Inventory Processing
-- Description: Hardware/software inventory processing failures
SELECT 
    [ResourceID],
    [Netbios_Name0] AS ComputerName,
    [LastHardwareScan],
    [LastSoftwareScan],
    [LastStatusMessage]
FROM 
    dbo.v_InventoryReport
WHERE 
    [LastStatusMessage] LIKE '%error%'
    OR [LastHardwareScan] < DATEADD(DAY, -30, GETDATE())
ORDER BY 
    [LastHardwareScan] ASC;

--Remediation:

  --  Client settings: Verify inventory settings in client policy

 --   MP/DP: Check management point communication

 --   Size limits: Review inventory size limits and classes

 --   Clients: Troubleshoot problematic clients individually

--

-- Error Type: SQL Agent Jobs
-- Description: Failed SQL Server Agent jobs (including SCCM maintenance)
USE msdb;
GO
SELECT 
    j.[name] AS JobName,
    j.[enabled],
    h.[run_date],
    h.[run_time],
    h.[run_duration],
    h.[message] AS ErrorMessage
FROM 
    sysjobs j
INNER JOIN 
    sysjobhistory h ON j.job_id = h.job_id
WHERE 
    h.run_status = 0 -- Failed
    AND h.run_date >= CONVERT(VARCHAR, GETDATE()-7, 112)
ORDER BY 
    h.run_date DESC, h.run_time DESC;

--Remediation:

 --   Job steps: Review failed job step details

 --   Schedules: Verify job schedules and dependencies

 --   Permissions: Check SQL Agent service account permissions

 --   Resources: Ensure adequate system resources

--17. Database Backup Status
--

-- Error Type: Backup Failures
-- Description: Verifies recent successful backups
USE msdb;
GO
SELECT 
    database_name,
    backup_start_date,
    backup_finish_date,
    type,
    CASE type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Transaction Log'
    END AS BackupType,
    is_damaged,
    has_backup_checksums
FROM 
    backupset
WHERE 
    database_name = 'CM_P01'
    AND backup_start_date >= DATEADD(DAY, -2, GETDATE())
ORDER BY 
    backup_start_date DESC;

Remediation:

    Failed backups: Check disk space, backup destination accessibility

    No recent backups: Verify backup jobs are running and scheduled

    Backup verification: Test restore procedures regularly

    Retention: Ensure adequate backup retention periods

18. TempDB Configuration Issues
sql

-- Error Type: TempDB Configuration
-- Description: Checks TempDB configuration for optimal performance
USE master;
GO
SELECT 
    name AS FileName,
    size * 8 / 1024 AS SizeMB,
    growth AS GrowthPages,
    is_percent_growth,
    physical_name
FROM 
    sys.master_files
WHERE 
    database_id = DB_ID('tempdb');

Remediation:

    Multiple data files: Create multiple TempDB data files (1 per CPU core)

    Growth settings: Set reasonable growth increments (not percentage)

    Location: Place TempDB on fast storage, separate from user databases

    Size: Pre-size TempDB to avoid autogrowth during operations

19. Database File Auto-growth Events
sql

-- Error Type: File Growth Issues
-- Description: Recent database file auto-growth events
SELECT 
    database_name,
    file_name,
    start_time,
    duration_seconds,
    growth_size_mb,
    growth_type
FROM 
    (SELECT 
        DB_NAME(database_id) AS database_name,
        mf.name AS file_name,
        start_time,
        DATEDIFF(SECOND, start_time, end_time) AS duration_seconds,
        (mf.size * 8) / 1024 AS growth_size_mb,
        CASE mf.is_percent_growth 
            WHEN 1 THEN 'Percent' 
            ELSE 'Pages' 
        END AS growth_type
    FROM 
        sys.dm_db_file_space_usage su
    INNER JOIN 
        sys.master_files mf ON su.file_id = mf.file_id AND su.database_id = mf.database_id
    ) AS file_stats
WHERE 
    database_name = 'CM_P01'
    AND start_time >= DATEADD(DAY, -1, GETDATE())
ORDER BY 
    start_time DESC;

Remediation:

    Frequent growth: Pre-size database files to minimize autogrowth

    Slow growth: Use fixed MB growth instead of percentage

    Performance: Monitor for growth during peak hours and reschedule

20. Overall Database Health Summary
sql

-- Error Type: Comprehensive Health Check
-- Description: Overall database health summary
SELECT 
    'Database Status' AS CheckType,
    DB_NAME() AS DatabaseName,
    DATABASEPROPERTYEX(DB_NAME(), 'Status') AS Status,
    DATABASEPROPERTYEX(DB_NAME(), 'Recovery') AS RecoveryModel,
    DATABASEPROPERTYEX(DB_NAME(), 'IsAutoShrink') AS AutoShrinkEnabled
UNION ALL
SELECT 
    'Space Usage' AS CheckType,
    DB_NAME() AS DatabaseName,
    CAST((SELECT size * 8.0 / 1024 FROM sys.database_files WHERE type = 0) AS VARCHAR) + ' MB' AS Status,
    CAST((SELECT size * 8.0 / 1024 FROM sys.database_files WHERE type = 1) AS VARCHAR) + ' MB' AS RecoveryModel,
    '' AS AutoShrinkEnabled;

-- Check for any open transactions older than 1 hour
SELECT 
    COUNT(*) AS LongRunningTransactions
FROM 
    sys.dm_tran_active_transactions at
INNER JOIN 
    sys.dm_tran_session_transactions st ON at.transaction_id = st.transaction_id
INNER JOIN 
    sys.dm_exec_sessions es ON st.session_id = es.session_id
WHERE 
    at.transaction_begin_time < DATEADD(HOUR, -1, GETDATE());

Remediation:

    Database status: Ensure database is online and accessible

    Space management: Monitor and manage database growth

    Long transactions: Identify and address blocking long-running transactions

    Regular maintenance: Implement comprehensive maintenance plan

Quick Health Check Script
sql

-- Quick overall health check
USE CM_P01;
GO

PRINT '=== SCCM DATABASE HEALTH CHECK ===';
PRINT 'Database: ' + DB_NAME();
PRINT 'Check Time: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '';

-- Basic database info
SELECT 
    'Database Info' AS CheckType,
    DB_NAME() AS DatabaseName,
    DATABASEPROPERTYEX(DB_NAME(), 'Status') AS Status,
    DATABASEPROPERTYEX(DB_NAME(), 'Recovery') AS RecoveryModel,
    (SELECT COUNT(*) FROM dbo.vSMS_ComponentSummarizer WHERE MessageType = 3 AND MessageTime >= DATEADD(HOUR, -24, GETDATE())) AS RecentComponentErrors,
    (SELECT COUNT(*) FROM dbo.vSMS_SiteSystemSummarizer WHERE Status <> 1) AS ProblematicSiteSystems;

--This comprehensive script will help you monitor your SCCM database health and provide specific remediation steps for each type of errorencountered. Run these queries regularly as part of your SCCM maintenance routine.
