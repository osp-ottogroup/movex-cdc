require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase

  test "process" do
    original_max_transaction_size   = Trixx::Application.config.trixx_max_transaction_size # Remember previous setting
    original_kafka_max_bulk_count   = Trixx::Application.config.trixx_kafka_max_bulk_count
    original_initial_worker_threads = Trixx::Application.config.trixx_initial_worker_threads

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      Trixx::Application.config.trixx_max_transaction_size   = 1000             # Ensure that two pass access is done in TransferThread.read_event_logs_batch
      Trixx::Application.config.trixx_kafka_max_bulk_count   = 100
      Trixx::Application.config.trixx_initial_worker_threads = 1                # Needed as long as test uses the same DB connection for all threads (different to development and production)

      # Set sequence to large value to test if numeric variables may deal with this large values, sequence will cycle within test
      # MaxValue for sequence is 999999999999999999
      Database.execute "ALTER SEQUENCE Event_Logs_SEQ INCREMENT BY 99999999999900000"   # MaxValue -999999, Distance to MaxValue should be greater than Cache size and max. increase factor 10
      Database.select_one "SELECT Event_Logs_SEQ.NextVal FROM Dual"
      Database.execute "ALTER SEQUENCE Event_Logs_SEQ INCREMENT BY 1"

      ['SYSDATE-1', 'SYSDATE-0.5', 'SYSDATE'].each do |created_at|              # ensure multiple partitions are filled with data
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

    ThreadHandling.get_instance.ensure_processing
    assert_equal(Trixx::Application.config.trixx_initial_worker_threads, ThreadHandling.get_instance.thread_count, 'Number of threads should run')

    loop_count = 0
    while loop_count < 30 do                                                    # wait up to x * 10 seconds for processing of event_logs records
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      if event_logs == 0                                                  # All records processed, no need to wait anymore
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

    if messages_to_process > successful_messages_processed                      # List remaining events from table
      puts "First 100 remaining events in table:"
      counter = 0
      Database.select_all("SELECT * FROM Event_Logs").each do |e|
        counter += 1
        puts e if counter <= 100
      end
    end

    assert_equal(messages_to_process, successful_messages_processed, 'Exactly the number of records in Event_Logs should be processed')
    assert_equal(0, message_processing_errors, 'There should not be processing errors')

    ThreadHandling.get_instance.shutdown_processing
    assert_equal(0, ThreadHandling.get_instance.thread_count, 'No threads should run after shutdown')
    assert_equal(0, Database.select_one("SELECT COUNT(*) FROM Event_Logs"), 'All event_logs should be processed after shutdown')

    Trixx::Application.config.trixx_max_transaction_size    = original_max_transaction_size   # Restore previous setting
    Trixx::Application.config.trixx_kafka_max_bulk_count    = original_kafka_max_bulk_count   # Restore previous setting
    Trixx::Application.config.trixx_initial_worker_threads  = original_initial_worker_threads # Restore previous setting

  end

end
