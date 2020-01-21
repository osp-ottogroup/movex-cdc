require 'test_helper'

class TransferThreadTest < ActiveSupport::TestCase

  test "create worker" do
    TransferThread.create_worker(1)
    sleep(1)
    # TODO: stop worker thread
  end

end
