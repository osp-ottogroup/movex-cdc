# Remove uninteresting debug messages from log

LOG=$1

cat $LOG |
grep -v "TransferThread DELETE with 1000 records" |
grep -v "delete_event_logs_batch" |
grep -v "select_all_limit fetch_limit=" |
grep -v "FROM   Event_Logs PARTITION" |
grep -v "WHERE  e.ID < :max_id" |
grep -v "WHERE  e.ID >= :max_id" |
grep -v "FOR UPDATE SKIP LOCKED" |
grep -v "records selected with following SQL" |
grep -v "app/models/table_less_oracle.rb:42:in " |
grep -v "Process event_logs_slice with 1000 records" |
grep -v "app/models/table_less.rb:12:in" |
grep -v "SELECT Partition_Name, High_Value FROM User_Tab_Partitions" |
grep -v " records in event_logs into " |
grep -v "TransferThread.check_record_cache_for_aging: Reset record cache after60 seconds" |
grep -v "app/models/transfer_thread.rb:394:in" |
grep -v "app/models/transfer_thread.rb:403:in" |
grep -v 'SELECT "TABLES".* FROM "TABLES" WHERE "TABLES"."ID" = :a1 ' |
grep -v 'SELECT "SCHEMAS".* FROM "SCHEMAS" WHERE "SCHEMAS"."ID" = :a1'
