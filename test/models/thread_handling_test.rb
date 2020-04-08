require 'test_helper'

class ThreadHandlingTest < ActiveSupport::TestCase

  test "process" do
    ThreadHandling.get_instance.ensure_processing
    assert_equal(Trixx::Application.config.trixx_initial_worker_threads, ThreadHandling.get_instance.thread_count, 'Number of threads should run')

    loop_count = 0
    while loop_count < 10 do                                                  # wait up to x seconds for processing of event_logs records
      loop_count += 1
      event_logs = TableLess.select_one("SELECT COUNT(*) FROM Event_Logs")
      break if event_logs == 0                                                # All records processed, no need to wait anymore
      sleep 1
    end

    ThreadHandling.get_instance.shutdown_processing
    assert_equal(0, ThreadHandling.get_instance.thread_count, 'No threads should run after shutdown')
    assert_equal(0, TableLess.select_one("SELECT COUNT(*) FROM Event_Logs"), 'All event_logs should be processed after shutdown')
  end

end
