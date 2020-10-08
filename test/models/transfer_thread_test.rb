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

    # Process records from event_log and restore previous app state
    def process_eventlogs(options = {})
      options[:max_wait_time]               = 20 unless options[:max_wait_time]
      options[:expected_remaining_records]  = 0  unless options[:expected_remaining_records]

      original_worker_threads = Trixx::Application.config.trixx_initial_worker_threads
      Trixx::Application.config.trixx_initial_worker_threads = 1                # Ensure that all keys are matching to this worker thread by MOD

      log_event_logs_content(console_output: false, caption: "#{options[:title]}: Event_Logs records before processing")

      # worker ID=0 for exactly 1 running worker
      worker = TransferThread.new(0, max_transaction_size: 10000, max_message_bulk_count: 1000, max_buffer_bytesize: 100000)  # Sync. call within one thread

      # Stop process in separate thread after 10 seconds because following call of 'process' will never end without that
      Thread.new do
        loop_count = 0
        while loop_count < options[:max_wait_time] do                           # wait up to x seconds for processing
        loop_count += 1
        event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
        Rails.logger.debug "#{event_logs} records remaining in Event_Logs"
        break if event_logs == options[:expected_remaining_records]             # All records processed, no need to wait anymore
        sleep 1
        end
        worker.stop_thread
      end

      worker.process                                                            # only synchrone execution ensures valid test of function

      remaining_event_log_count = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      log_event_logs_content(console_output: true, caption: "#{options[:title]}: Event_Logs records after processing") if remaining_event_log_count > options[:expected_remaining_records]   # List remaining events from table

      Trixx::Application.config.trixx_initial_worker_threads = original_worker_threads  # Restore possibly differing value
      remaining_event_log_count
    end

    create_event_logs_for_test(10)
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Regular processing of all records')
    assert_equal 0, remaining_event_log_count, 'All Records from Event_Logs should be processed and deleted now'

    create_event_logs_for_test(10)
    EventLog.last.update!(retry_count: 1, last_error_time: Time.now+20000)  # set erroneous, keep in mind that DB time and client time may differ in time zone
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 1, title: 'Processing with one error record')
    assert_equal 1, remaining_event_log_count, 'All Records from Event_Logs except the one erroneous should be processed and deleted now'

    EventLog.last.update!(last_error_time: Time.now-20000)  # set timestamp so remaining erroneous record should be processed now
    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Processing the one error record')
    assert_equal 0, remaining_event_log_count, 'Last error record from Event_Logs should be processed and deleted now'
  end

end
