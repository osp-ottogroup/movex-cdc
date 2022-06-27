# MOVEX Change Data Capture: Release notes
## Upcoming next release
- Encrpyted SQL*Net connection if server has SQLNET.ENCRYPTION_SERVER != rejected<br>
  Requires release of v6.1.7 for https://github.com/rsim/oracle-enhanced as precondition (https://github.com/rsim/oracle-enhanced/pull/2284)

## 2022-06-27 Release 1.10.2
- Optimization: Test for DB-locks/pending transactions on partitions of Event_Logs only once instead for each partition
- New feature: API method for rescheduling final errors for transfer to Kafka (all, events of particular schema, eventts of particular table)
- Bugfix: Load of css file from external URL removed 

## 2022-06-13 Release 1.10.1
- Bugfix: Correct timezone set for event timestamp if DB timezone is not GMT
- Configuration parameter DB_DEFAULT_TIMEZONE added to change the DB timezone under rare conditions
- Flashback query for topic initialization is optional now

## 2022-06-02 Release 1.10.0
- Configuration parameter KAFKA_SSL_CA_CERT supports file(s) with multiple pem-formatted certificates now as well as a comma-separated list of multiple file paths.<br>
  This way correct authentication with SASL_SSL is possible without system certicates.  

## 2022-05-24 Release 1.9.1
- separate property for KAFKA_SSL_CLIENT_CERT_CHAIN to set the file with the client CA certificate chain if needed
- control max. sleep time for idle workers by MAX_WORKER_THREAD_SLEEP_TIME (default 60 seconds)
- Set health check result to unhealthy if number of existing partitions exceeds threshold MAX_PARTITIONS_TO_COUNT_AS_HEALTHY

## 2022-04-27 Release 1.9.0
- For Oracle Standard Edition rsp. Enterprise Edition without Partitioning Option the staging table Event_Logs now has an index on column ID for appropriate performance
- Config parameter MAX_FAILED_LOGONS_BEFORE_ACCOUNT_LOCKED introduced
- Oracle-DB: Subselects in trigger conditions are supported now. Allows inclusion of other tables in filter conditions.
- Optional ORDER clause for initialization. Allows guaranteed order for initial load.
- Support for sub-paths in URL like for nginx locations. Config parameter PUBLIC_PATH introduced for this purpose.
- Support for Kafka connections by SASL_PLAIN or SASL_SSL with user and password added.<br>
  Config parameters KAFKA_SASL_PLAIN_USERNAME, KAFKA_SASL_PLAIN_PASSWORD and KAFKA_SSL_CA_CERTS_FROM_SYSTEM added for this purpose.

## 2022-04-04 Release 1.8.0
- Docker images are available at Docker hub now.
- Enhanced API for import and export of configuration
- Check for orphaned triggers at trigger deployment
- Oracle: get sequence from user_sequences instead of currval to avoid ORA-08002
- Bugfix: Ensure that import of configuration leaves the original IDs in config untouched
- Bugfix: Close SQL cursor in case of SQL exception

## 2022-01-19 Release 1.6.0
- Retry processing after Kafka::ConcurrentTransactionError
- Show instance configuration in frontend