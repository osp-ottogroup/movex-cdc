# MOVEX Change Data Capture: Release notes
## Upcoming next release

# 2025-10-23 1.13.3
- Bugfix: Correct writing of pending statistics after termination of worker threads at shutdown

# 2025-10-22 1.13.2
- Optional suppression of non-pkey columns in JSON payload of events. <br/>
  This allows to send only primary key columns but react on changes of marked columns.<br/>
  Used to process small change events in Kafka without sending the whole set of interested columns.<br/>
  These columns can be gotten from the source table in a following step possibly after additional filtering and deduplication.<br/>

# 2025-10-02 1.13.1
- SQL expressions for JSON attributes are supported now in addition to table columns. This allows to include values from joined tables in the JSON event.
- SQL expressions for the message key are supported now as fifth type of key definition. This allows to include values from joined tables in the message key.
- JDBC statement cache reduced from 100 to 50 to avoid ORA-01000: maximum number of open cursors exceeded   
- New configuration parameter MEMORY_COLLECTION_FLUSH_LIMIT introduced to control the memory consumption of the in-memory collection of change events before flushing to DB. Default is 1,000 events.
- New configuration parameter SYSTEM_VALIDATION_JOB_CYCLE introduced to control the job for housekeeping and worker thread restart. Default is 60 seconds.

## 2025-09-16 1.12.4.1
- Bufix: Bind variables are used for hearbeat check to prevent from ORA-01000: maximum number of open cursors exceeded

## 2025-09-10 1.12.4
- Encrpyted SQL*Net connection is requested by client now by default (oracle.net.encryption_client=REQUESTED)
- Framework dependencies upgraded: JRuby 10.0.2.0, Rails 8.0.2.1, Kafka client 3.9.1

## 2025-09-02 1.12.3
- Abort processing of a batch if certain Kafka errors occur. This avoids endless retries with divide & conquer processing.
- Add the timestamp of worker thread start to the transactional ID of the Kafka producer to avoid collisions of transactional IDs if a worker thread is restarted quickly after termination.
- Use new transactional ID each time a new Kafka producer is created
- Config attribute KAFKA_MAX_BULK_COUNT is not used anymore
- Config attribute KAFKA_TRANSACTION_TIMEOUT added with default 10 minutes

## 2025-08.13 1.12.2
- Role based privileges are accepted to show tables in configuration dialog,
  if the role is a default role or has an authentication type = 'NONE'.
  Before only default roles were accepted.
- SELECT or READ privilege on DBA_ROLES is required now for the MOVEX CDC schema owner in addition to DBA_ROLE_PRIVS.

## 2025-08-04 1.12.1
- Bugfix: The format of the 'timestamp' field in the Kafka event is now an exact ISO 8601 format with microseconds and the default timezone of the DB server (e.g. 2025-08-04T12:34:56.789456+02:00).<br/>
  The comma before the fraction is replaced by dot to ensure correct ISO 8601 compatibility.<br/>
  For backward compatibility with previously used formats there is a configuration parameter LEGACY_TS_FORMAT with two possible values:
  - TYPE_1: ISO 8601-like format but with comma instead of dot as fraction delimiter and with timezone of local machine without a colon (e.g. 2025-08-04T12:34:56,789456+0200)<br/>
    This was the default format before release 1.10.1 of 2022-06-13.
  - TYPE_2: ISO 8601-like format but with with comma instead of dot as fraction delimiter (e.g. 2025-08-04T12:34:56,789456+02:00)<br/>
    This was the default format before release 1.12.1 of 2025-08-04.
- Warning only if configuration items are duplicated in client.properties as long as the values are the same (instead of hard error).

## 2025-07-29 1.11.8
- Bugfix: Accept SSL keystore config also if declared in run_config.yml or environment and not declared in property file 
- Close DB connection at termination of worker thread so new worker thread always gets a new fresh connection

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
- Timeout at commit_transaction may raise IllegalStateException at following abort_transaction, caught now
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