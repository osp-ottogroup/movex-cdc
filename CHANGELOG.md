# MOVEX Change Data Capture: Release notes
## Upcoming next release
- Encrpyted SQL*Net connection if server has SQLNET.ENCRYPTION_SERVER != rejected<br>
  Requires release of v6.1.7 for https://github.com/rsim/oracle-enhanced as precondition (https://github.com/rsim/oracle-enhanced/pull/2284)

## 2025-06-26 1.11.7
- Bugfix: Mock implementation for Kafka producer accepts all configured topics now (KAFKA_CLIENT_LIBRARY: mock)

## 2025-06-19 1.11.6
- Support for SSL connection without client authentication (keystore) added

## 2025-05-28 1.11.5
- Separate library for zstd compression added

## 2025-05-27 1.11.4
- Check for 90% limit at use of Java heap memory in health check
- Update Kafka client lib to 3.9.1 and log4j to 2.24.3
- Reduce the number of producer retries from 5 to 1 because divide & conquer does the same job
- Replace infinite wait for producer.close if Kafka broker is not available with defined timeout specified by KAFKA_PRODUCER_TIMEOUT
- Adjust also log4j log level at runtime changes of log level

## 2025-05-26 1.11.
- Docker container becomes unhealthy if regular job cycle is exceeded by factor of 10
- Jobs are not restarted at massive job execution delay possibly due to out of memory, this should by handled outside the container with restart of container
- Timeout at commit_transaction may raise IllegalStateException at following abort_transaction, catched now
## 2025-05-20 1.11.2
- Alternative Ruby client library for Kafka removed, using only Apache Kafka client library now
- The number of created change events at initialization is recorded now in activity logs
- More than 0 error records in table Event_Log_Final_Errors cause healft check to fail now
- Transactions for batch processing of Kafka producer are cancelled and quickly rolled back at first occurrence of an error. Divide & conquer follows. 

## 2025-04-03 1.11.1
- The default library controlled by KAFKA_CLIENT_LIBRARY is changed to 'java' in the next release. The ruby-kafka library will be removed in a future release.
- An additional configuration KAFKA_TRANSACTIONAL_ID_PREFIX allows to adjust the used prefix for the unique transactional ID

## 2023 Release 1.11.0
- Alternative connection to Kafka available via Apache Client Library
- The previously used connection via ruby-kafka is still available as primary type
- Additional configuration parameters are added:
  - KAFKA_CLIENT_LIBRARY: 'ruby' or 'java'<br>
    Controls the used library for Kafka connection. Default is still 'ruby' but will be switched to 'java' in a coming relase. 
  - KAFKA_SECURITY_PROTOCOL: PLAINTEXT, SASL_PLAINTEXT, SASL_SSL or SSL<br>
    This setting becomes mandatory if KAFKA_CLIENT_LIBRARY is set to 'java'.

## 2023-08-21 Release 1.10.17
- Bugfix: Ensure that increasing the high value of the oldest partition works also if there is not high value gap between first and second partition  

## 2023-06-21 Release 1.10.16
- API functions /db_triggers/generate and /db_triggers/generate_all return http status code 207 (Multi-Status) if DB errors occur at trigger generation

## 2023-06-15 Release 1.10.15
- Bugfix: Ensure timestamp fraction delimiter for Oracle release < 19.1 is always a dot no matter which language setting is active
- ROWID values encapsulated in ROWIDTOCHAR() function for before JSON_OBJECT

## 2022-12-13 Release 1.10.11
- Bugfix: wrong URL for css file after docker start with suffixed URL

## 2022-11-14 Release 1.10.10
- CloudEvents header at Kafka events possible per source table

## 2022-10-09 Release 1.10.9
- Update to OpenJDK 19, jRuby 9.3.8.0, Kafka 3.2.3, Rails 6.1.7
- Bugfix: constant public path for materialdesignicons_5.4.55.min.css even after multiple docker start
- Bugfix: 'risk of infinite loop. Cancelled now!': Calculation of selected range adjusted for resilience accoring to this error

## 2022-09-15 Release 1.10.8
- Bugfix: TypeError:no implicit conversion of Symbol into Integer in debug output
- Log also original attributes before updated in Activity_Logs

## 2022-09-13 Release 1.10.7
- Bugfix: Assume missing relations as empty in config file at config import

## 2022-09-01 Release 1.10.6
- Bugfix: Accept multiple calls to health check within a second if authorized with valid JWT
- Updated jRuby runtime

## 2022-08-25 Release 1.10.5
- Bugfix: support insert conditions with subselects for initial import

## 2022-08-22 Release 1.10.4
- Update Rails to current version
- Bugfix: Show GUI icons in all cases
- Bugfix: support deployment parameter "dry_run" as string ("dry_run"="false") like it is used by curl

## 2022-07-11 Release 1.10.3
- Use Java 18 runtime
- Size of Docker image reduced

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

## 2021-12-06 Start offering product as open source