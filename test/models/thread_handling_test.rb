require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase

  test "process" do
    ThreadHandling.get_instance.ensure_processing
    assert_equal(ThreadHandling::INITIAL_NUMBER_OF_THREADS, ThreadHandling.get_instance.thread_count, 'Number of threads should run')

    sleep 3                                                                     # let workers start work
    ThreadHandling.get_instance.shutdown_processing
    assert_equal(0, ThreadHandling.get_instance.thread_count, 'No threads should run after shutdown')
  end

end
