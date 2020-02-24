require 'test_helper'

class TransferThreadTest < ActiveSupport::TestCase

  test "create worker" do
    worker = TransferThread.create_worker(1)                                    # Async. thread
    sleep(3)
    worker.stop_thread
  end

  test "process" do
    worker = TransferThread.new(1)                                              # Sync. call within one thread
    Thread.new{ sleep 10; worker.stop_thread }                                  # Stop process after 10 seconds
    worker.process
  end

end
