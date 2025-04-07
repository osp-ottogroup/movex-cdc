require 'test_helper'

class TransferThreadTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  # Not necessary because tested by ThreadHandling
  # This test is problematic because Thread remains working after worker.stop_thread
  #test "create worker" do
  #  worker = TransferThread.create_worker(2, max_transaction_size: 10000) # Async. thread
  #  sleep(1)
  #  worker.stop_thread
  #end


  test "process" do
    run_with_current_user { create_event_logs_for_test(20) }
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Regular processing of all records')
    assert_equal 0, remaining_event_log_count, log_on_failure('All Records from Event_Logs should be processed and deleted now')

    run_with_current_user { create_event_logs_for_test(20) }
    EventLog.last.update!(retry_count: 1, last_error_time: Database.systime+20000)  # set erroneous, keep in mind that DB time and client time may differ in time zone
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 1, title: 'Processing with one error record')
    assert_equal 1, remaining_event_log_count, log_on_failure('All Records from Event_Logs except the one erroneous should be processed and deleted now')

    EventLog.last.update!(last_error_time: Database.systime-20000)  # set timestamp so remaining erroneous record should be processed now
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Processing the one error record')
    assert_equal 0, remaining_event_log_count, log_on_failure('Last error record from Event_Logs should be processed and deleted now')
  end

  test "process with error" do
    # Save original state
    org_error_retry_start_delay = MovexCdc::Application.config.error_retry_start_delay
    org_error_max_retries       = MovexCdc::Application.config.error_max_retries

    # Test error handling with too huge message
    Database.execute "DELETE FROM Event_Logs"                               # precondition for valid counters
    Database.execute "DELETE FROM Event_Log_Final_Errors"
    StatisticCounterConcentrator.get_instance.flush_to_db                       # ensure pending Statistics records from memory are flushed to DB
    Database.execute "DELETE FROM Statistics"                               # Remove previous existing value to ensure valid assertions

    MovexCdc::Application.config.error_retry_start_delay = 1000
    temp_table = Table.new(schema_id:  victim_schema.id,
                           name:       'TEMP_DUMMY',
                           info:       'Only for temporary use',
                           topic:      'Non-existing topic')
    run_with_current_user do
      create_event_logs_for_test(20)
      temp_table.save!
    end
    EventLog.last.update!(table_id: temp_table.id)
    run_with_current_user { create_event_logs_for_test(20) }                    # create another records to ensure error is in the middle
    remaining_event_log_count = process_eventlogs(max_wait_time: 30, expected_remaining_records: 1, title: 'Process all eventlogs except one with huge payload')
    log_event_logs_content(console_output: true) if remaining_event_log_count <= 0 || remaining_event_log_count >= 3 # List remaining events from table
    assert remaining_event_log_count>0 && remaining_event_log_count<3 , log_on_failure("One event_Log record with non existing topic should cause processing error! remaining_event_log_count = #{remaining_event_log_count}")

    MovexCdc::Application.config.error_retry_start_delay = 1                 # ensure retry processing takes place now
    MovexCdc::Application.config.error_max_retries = 3                 # ensure retry processing takes place now
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Process remaining erroneous record')


    assert_equal 0, remaining_event_log_count, log_on_failure('The remaining erroneous record should be moved to final error now')
    assert_equal 1, Database.select_one("SELECT COUNT(*) FROM Event_Log_Final_Errors"), log_on_failure('The remaining erroneous record should exist in final errors now')

    StatisticCounterConcentrator.get_instance.flush_to_db       # ensure Statistics records are in DB
    # Database.select_all("SELECT * FROM Statistics").each do |s|
    #   puts s
    # end

    table_id = victim1_table.id
    # possibly too volatile tests if partition change is included in test data, use max_expected: to cover this
    assert_statistics(expected: 25, table_id: table_id,       operation: 'I', column_name: :events_success)
    assert_statistics(expected: 0,  table_id: table_id,       operation: 'I', column_name: :events_delayed_errors, max_expected: 1) # Final error state could by reached within test
    assert_statistics(expected: 3,  table_id: temp_table.id,  operation: 'I', column_name: :events_delayed_errors, max_expected: 4)
    assert_statistics(expected: 1,  table_id: temp_table.id,  operation: 'I', column_name: :events_final_errors)
    assert_statistics(expected: 28, table_id: table_id,       operation: 'I', column_name: :events_d_and_c_retries, max_expected: 38)
    assert_statistics(expected: 2,  table_id: temp_table.id,  operation: 'I', column_name: :events_d_and_c_retries)
    assert_statistics(expected: 3,  table_id: temp_table.id,  operation: 'I', column_name: :events_delayed_retries, max_expected: 4)

    assert_statistics(expected: 4,  table_id: table_id, operation: 'U', column_name: :events_success)
    assert_statistics(expected: 0,  table_id: table_id, operation: 'U', column_name: :events_delayed_errors)
    assert_statistics(expected: 0,  table_id: table_id, operation: 'U', column_name: :events_final_errors)
    assert_statistics(expected: 4,  table_id: table_id, operation: 'U', column_name: :events_d_and_c_retries,  max_expected: 8)
    assert_statistics(expected: 0,  table_id: table_id, operation: 'U', column_name: :events_delayed_retries)

    assert_statistics(expected: 4,  table_id: table_id, operation: 'D', column_name: :events_success)
    assert_statistics(expected: 0,  table_id: table_id, operation: 'D', column_name: :events_delayed_errors)
    assert_statistics(expected: 0,  table_id: table_id, operation: 'D', column_name: :events_final_errors)
    assert_statistics(expected: 4,  table_id: table_id, operation: 'D', column_name: :events_d_and_c_retries, max_expected: 6)
    assert_statistics(expected: 0,  table_id: table_id, operation: 'D', column_name: :events_delayed_retries)

    # Restore previous settings
    Database.execute "DELETE FROM Statistics"
    run_with_current_user { temp_table.destroy! }                                              # remove temporary table
    MovexCdc::Application.config.error_retry_start_delay = org_error_retry_start_delay
    MovexCdc::Application.config.error_max_retries       = org_error_max_retries
  end
end
