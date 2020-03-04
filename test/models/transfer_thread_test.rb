require 'test_helper'

class TransferThreadTest < ActiveSupport::TestCase

  test "create worker" do
    worker = TransferThread.create_worker(1)                                    # Async. thread
    sleep(1)
    worker.stop_thread
  end

  test "process" do
    worker = TransferThread.new(1)                                              # Sync. call within one thread

    # Stop process in separate thread after 10 seconds because following call of 'process' will never end without that
    Thread.new do
      loop_count = 0
      while loop_count < 10 do                                                  # wait up to x seconds for processing
        loop_count += 1
        event_logs = TableLess.select_one("SELECT COUNT(*) FROM Event_Logs")
        break if event_logs == 0                                                # All records processed, no need to wait anymore
        sleep 1
      end
      worker.stop_thread
    end

    worker.process
    assert_equal 0, TableLess.select_one("SELECT COUNT(*) FROM Event_Logs"), 'All Records from Event_Logs should be processed and deleted now'
  end

end
