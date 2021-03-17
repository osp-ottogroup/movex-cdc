require 'test_helper'

class TransferThreadTest < ActiveSupport::TestCase
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

  test "create worker" do
    worker = TransferThread.create_worker(2, max_transaction_size: 10000, max_message_bulk_count: 1000, max_buffer_bytesize: 100000) # Async. thread
    sleep(1)
    worker.stop_thread
  end


  test "process" do
    create_event_logs_for_test(20)
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Regular processing of all records')
    assert_equal 0, remaining_event_log_count, 'All Records from Event_Logs should be processed and deleted now'

    create_event_logs_for_test(20)
    EventLog.last.update!(retry_count: 1, last_error_time: Time.now+20000)  # set erroneous, keep in mind that DB time and client time may differ in time zone
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 1, title: 'Processing with one error record')
    assert_equal 1, remaining_event_log_count, 'All Records from Event_Logs except the one erroneous should be processed and deleted now'

    EventLog.last.update!(last_error_time: Time.now-20000)  # set timestamp so remaining erroneous record should be processed now
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Processing the one error record')
    assert_equal 0, remaining_event_log_count, 'Last error record from Event_Logs should be processed and deleted now'

  end

  test "process with error" do
    # Test error handling with too huge message
    Database.execute "DELETE FROM Event_Logs"                                   # precondition for valid counters
    Database.execute "DELETE FROM Event_Log_Final_Errors"
    StatisticCounterConcentrator.get_instance.flush_to_db                       # ensure pending Statistics records from memory are flushed to DB
    Database.execute "DELETE FROM Statistics"                                   # Remove previous existing value to ensure valid assertions

    Trixx::Application.config.trixx_error_retry_start_delay = 1000              # ensure no retry processing takes place
    create_event_logs_for_test(20)
    huge_payload = "\"payload\": \""
    1.upto(1024*105){ huge_payload << "0123456789"}  # more than 1 MB
    huge_payload << "\""
    EventLog.last.update!(payload: huge_payload)
    create_event_logs_for_test(20)                                              # create another records to ensure error is in the middle
    remaining_event_log_count = process_eventlogs(max_wait_time: 30, expected_remaining_records: 1, title: 'Process all eventlogs except one with huge payload')
    assert_equal 1, remaining_event_log_count, 'One event_Log record with huge payload should cause processing error'

    Trixx::Application.config.trixx_error_retry_start_delay = 1                 # ensure retry processing takes place now
    Trixx::Application.config.trixx_error_max_retries = 3                 # ensure retry processing takes place now
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Process remaining erroneous record')
    assert_equal 0, remaining_event_log_count, 'The remaining erroneous record should be moved to final error now'
    assert_equal 1, Database.select_one("SELECT COUNT(*) FROM Event_Log_Final_Errors"), 'The remaining erroneous record should exist in final errors now'

    StatisticCounterConcentrator.get_instance.flush_to_db       # ensure Statistics records are in DB
    # Database.select_all("SELECT * FROM Statistics").each do |s|
    #   puts s
    # end

    # possibly too volatile tests if partition change is included in test data, use max_expected: to cover this
    assert_statistics(expected: 25, table_id: 4, operation: 'I', column_name: events_success)
    assert_statistics(expected: 3,  table_id: 4, operation: 'I', column_name: :events_delayed_errors)
    assert_statistics(expected: 1,  table_id: 4, operation: 'I', column_name: :events_final_errors)
    assert_statistics(expected: 30, table_id: 4, operation: 'I', column_name: :events_d_and_c_retries)
    assert_statistics(expected: 3,  table_id: 4, operation: 'I', column_name: :events_delayed_retries)

    assert_statistics(expected: 4,  table_id: 4, operation: 'U', column_name: :events_success)
    assert_statistics(expected: 0,  table_id: 4, operation: 'U', column_name: :events_delayed_errors)
    assert_statistics(expected: 0,  table_id: 4, operation: 'U', column_name: :events_final_errors)
    assert_statistics(expected: 4,  table_id: 4, operation: 'U', column_name: :events_d_and_c_retries,  max_expected: 8)
    assert_statistics(expected: 0,  table_id: 4, operation: 'U', column_name: :events_delayed_retries)

    assert_statistics(expected: 4,  table_id: 4, operation: 'D', column_name: :events_success)
    assert_statistics(expected: 0,  table_id: 4, operation: 'D', column_name: :events_delayed_errors)
    assert_statistics(expected: 0,  table_id: 4, operation: 'D', column_name: :events_final_errors)
    assert_statistics(expected: 4,  table_id: 4, operation: 'D', column_name: :events_d_and_c_retries)
    assert_statistics(expected: 0,  table_id: 4, operation: 'D', column_name: :events_delayed_retries)
 end

end
