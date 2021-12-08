require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "process" do
    original_max_transaction_size   = MovexCdc::Application.config.max_transaction_size # Remember previous setting
    original_kafka_max_bulk_count   = MovexCdc::Application.config.kafka_max_bulk_count
    original_initial_worker_threads = MovexCdc::Application.config.initial_worker_threads

    Database.execute "DELETE FROM Event_Logs"                                   # Ensure table is empty before testing with super-large sequences

    Rails.logger.debug "ThreadHandlingTest.process: Create Event_Log_Records"
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      MovexCdc::Application.config.max_transaction_size   = 1000             # Ensure that two pass access is done in TransferThread.read_event_logs_batch
      MovexCdc::Application.config.kafka_max_bulk_count   = 100
      MovexCdc::Application.config.initial_worker_threads = 1                      # Needed as long as test uses the same DB connection for all threads (different to development and production)

      # Set sequence to large value to test if numeric variables may deal with this large values, sequence will cycle within test
      # MaxValue for sequence is 999999999999999999
      Database.execute "DROP SEQUENCE Event_Logs_SEQ"
      Database.execute "CREATE SEQUENCE Event_Logs_SEQ MAXVALUE 999999999999999999 CACHE 100000 CYCLE START WITH 99999999999900000"

      ['SYSDATE', 'SYSDATE+0.5', 'SYSDATE+1'].each do |created_at|              # ensure multiple partitions are filled with data, Partitions are created only for newer dates, else MIN is used
        # Store enough messages to provoke Oracle JDBC error in returning affected number of rows at executeUpdate
        Database.execute "INSERT INTO Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Msg_Key, Created_At)
                     SELECT Event_Logs_Seq.NextVal, #{tables_table.id}, 'I', 'Hugo', '  \"new\": {\n    \"ID\": 1\n  }',
                            CASE WHEN RowNum BETWEEN 674 AND 2356 THEN 'Fixed Value'
                            ELSE
                              CASE WHEN MOD(RowNum, 11) = 0 AND RowNum NOT BETWEEN 3030 AND 4122 THEN TO_CHAR(MOD(RowNum, 100)) ELSE NULL END
                            END, /* Ensure Msg_Key with different values and null */
                            #{created_at}
                     FROM DUAL
                     CONNECT BY Level <= 6174 /* Ensure last bulk array is not completely filled */
      "
      end
    else
      MovexCdc::Application.config.max_transaction_size = 100                # Ensure that two pass access is done in TransferThread.read_event_logs_batch
      MovexCdc::Application.config.kafka_max_bulk_count = 10
      MovexCdc::Application.config.initial_worker_threads = 1                      # Needed as long as test uses the same DB connection for all threads (different to development and production)
      create_event_logs_for_test(1000)
    end

    messages_to_process = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
    Rails.logger.debug "ThreadHandlingTest.process: #{messages_to_process} Event_Logs records before processing"
    log_event_logs_content(console_output: false)
    ThreadHandling.get_instance.ensure_processing
    assert_equal(MovexCdc::Application.config.initial_worker_threads, ThreadHandling.get_instance.thread_count, 'Number of threads should run')

    Rails.logger.debug "ThreadHandlingTest.process: wait for processing finished"
    loop_count = 0
    while loop_count < 200 do                                                    # wait up to 200 seconds for processing of event_logs records
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      if event_logs == 0                                                        # All records processed, no need to wait anymore
        Rails.logger.debug "Loop terminated because Event_Logs is Empty now"
        break
      end
      sleep 1
    end

    # Check if the number of processed messages matches with amount to process
    successful_messages_processed   = 0
    message_processing_errors       = 0
    health_check_data = ThreadHandling.get_instance.health_check_data
    Rails.logger.info "Health check data: #{health_check_data}"
    health_check_data.each do |hd|
      successful_messages_processed  += hd[:successful_messages_processed]
      message_processing_errors      += hd[:message_processing_errors]
    end

    log_event_logs_content(console_output: true) if messages_to_process > successful_messages_processed # List remaining events from table

    assert_equal(messages_to_process, successful_messages_processed, 'Exactly the number of records in Event_Logs should be processed')
    assert_equal(0, message_processing_errors, 'There should not be processing errors')

    Rails.logger.debug "ThreadHandlingTest.process: shutdown processing of threads"
    ThreadHandling.get_instance.shutdown_processing
    assert_equal(0, ThreadHandling.get_instance.thread_count, 'No threads should run after shutdown')
    assert_equal(0, Database.select_one("SELECT COUNT(*) FROM Event_Logs"), 'All event_logs should be processed after shutdown')

    MovexCdc::Application.config.max_transaction_size    = original_max_transaction_size   # Restore previous setting
    MovexCdc::Application.config.kafka_max_bulk_count    = original_kafka_max_bulk_count   # Restore previous setting
    MovexCdc::Application.config.initial_worker_threads  = original_initial_worker_threads # Restore previous setting

    # Drop all partitions from Event_Log after test to ensure next record with correct created_at will create new partition and not store records in first partition
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if MovexCdc::Application.partitioning?
        Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Interval = 'YES'").each do |p|
          begin
            Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p.partition_name}"
          rescue Exception => e
            Rails.logger.error "#{e.class}:#{e.message}: while trying to drop partition #{p.partition_name}! Current existing partitions follows:"
            Database.select_all("SELECT * FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' ORDER BY Partition_Position").each do |p|
              msg = "Partition #{p.partition_name} Pos=#{p.partition_position} High_Value=#{p.high_value} Interval=#{p.interval} Position=#{p.partition_position}"
              Rails.logger.debug msg
              puts msg
            end
            raise
          end
        end
      end
    end

  end

end

