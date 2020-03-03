require 'test_helper'

class TransferThreadTest < ActiveSupport::TestCase

  test "create worker" do
    worker = TransferThread.create_worker(1)                                    # Async. thread
    sleep(3)
    worker.stop_thread
  end

  test "process" do
    worker = TransferThread.new(1)                                              # Sync. call within one thread
    Thread.new{ sleep 10; worker.stop_thread }                                  # Stop process after 10 seconds because following call of process will never end without that
    worker.process
    assert_equal 0, TableLess.select_one("SELECT COUNT(*) FROM Event_Logs"), 'All Records from Event_Logs whould be processed and deleted now'
  end

end
