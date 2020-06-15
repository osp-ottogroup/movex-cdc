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
      # Store enough messages to provoke Oracle JDBC error in returning affected number of rows at executeUpdate
      Database.execute "INSERT INTO Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Created_At)
                       SELECT Event_Logs_Seq.NextVal, 1, 'I', 'Hugo', 'Dummy', SYSDATE
                       FROM DUAL
                       CONNECT BY Level <= 10000
      "
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
    while loop_count < 80 do                                                    # wait up to x * 10 seconds for processing of event_logs records
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      break if event_logs == 0                                                  # All records processed, no need to wait anymore
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
