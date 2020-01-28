require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase

  test "process" do
    ThreadHandling.get_instance.ensure_processing
  end

end
