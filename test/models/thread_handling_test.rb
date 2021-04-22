require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)
  end

  teardown do
    # Remove victim structures
    drop_victim_structures(@victim_connection)
    logoff_victim_connection(@victim_connection)
  end

  test "process" do
    original_max_transaction_size   = Trixx::Application.config.trixx_max_transaction_size # Remember previous setting
    original_kafka_max_bulk_count   = Trixx::Application.config.trixx_kafka_max_bulk_count
    original_initial_worker_threads = Trixx::Application.config.trixx_initial_worker_threads

    Database.execute "DELETE FROM Event_Logs"                                   # Ensure table is empty before testing with super-large sequences

    Rails.logger.debug "ThreadHandlingTest.process: Create Event_Log_Records"
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      Trixx::Application.config.trixx_max_transaction_size   = 1000             # Ensure that two pass access is done in TransferThread.read_event_logs_batch
      Trixx::Application.config.trixx_kafka_max_bulk_count   = 100
      Trixx::Application.config.trixx_initial_worker_threads = 1                # Needed as long as test uses the same DB connection for all threads (different to development and production)

      # Set sequence to large value to test if numeric variables may deal with this large values, sequence will cycle within test
      # MaxValue for sequence is 999999999999999999
      curval = Database.select_one "SELECT Event_Logs_SEQ.NextVal FROM Dual"
      Rails.logger.debug "Current value of Event_Logs_SEQ was #{curval}"
      Database.execute "DROP SEQUENCE Event_Logs_SEQ"
      Database.execute "CREATE SEQUENCE Event_Logs_SEQ MAXVALUE 999999999999999999 CACHE 100000 CYCLE START WITH #{99999999999900000 + curval}"

      ['SYSDATE', 'SYSDATE+0.5', 'SYSDATE+1'].each do |created_at|              # ensure multiple partitions are filled with data, Partitions are created only for newer dates, else MIN is used
        # Store enough messages to provoke Oracle JDBC error in returning affected number of rows at executeUpdate
        Database.execute "INSERT INTO Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Msg_Key, Created_At)
                     SELECT Event_Logs_Seq.NextVal, 1, 'I', 'Hugo', '  \"new\": {\n    \"ID\": 1\n  }',
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
      Trixx::Application.config.trixx_max_transaction_size = 100                 # Ensure that two pass access is done in TransferThread.read_event_logs_batch
      Trixx::Application.config.trixx_kafka_max_bulk_count = 10
      Trixx::Application.config.trixx_initial_worker_threads = 1                # Needed as long as test uses the same DB connection for all threads (different to development and production)
      create_event_logs_for_test(1000)
    end

    messages_to_process = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
    Rails.logger.debug "ThreadHandlingTest.process: #{messages_to_process} Event_Logs records before processing"
    log_event_logs_content(console_output: false)
    ThreadHandling.get_instance.ensure_processing
    assert_equal(Trixx::Application.config.trixx_initial_worker_threads, ThreadHandling.get_instance.thread_count, 'Number of threads should run')

    Rails.logger.debug "ThreadHandlingTest.process: wait for processing finished"
    loop_count = 0
    while loop_count < 20 do                                                    # wait up to x * 10 seconds for processing of event_logs records
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      if event_logs == 0                                                        # All records processed, no need to wait anymore
        Rails.logger.debug "Loop terminated because Event_Logs is Empty now"
        break
      end
      sleep 10
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

    Trixx::Application.config.trixx_max_transaction_size    = original_max_transaction_size   # Restore previous setting
    Trixx::Application.config.trixx_kafka_max_bulk_count    = original_kafka_max_bulk_count   # Restore previous setting
    Trixx::Application.config.trixx_initial_worker_threads  = original_initial_worker_threads # Restore previous setting

    # Drop all partitions from Event_Log after test to ensure next record with correct created_at will create new partition and not store records in MIN-partition
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      if Trixx::Application.partitioning?
        Database.select_all("SELECT Partition_Name FROM User_Tab_Partitions WHERE Table_Name = 'EVENT_LOGS' AND Partition_Name != 'MIN' ").each do |p|
          Database.execute "ALTER TABLE Event_Logs DROP PARTITION #{p['partition_name']}"
        end
      end
    end

  end

end

