require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase

  test "process" do
    ThreadHandling.get_instance.ensure_processing
    assert_equal(ThreadHandling::INITIAL_NUMBER_OF_THREADS, ThreadHandling.get_instance.thread_count, 'Number of threads should run')
  end

end
