require 'test_helper'

class ApplicationJobTest < ActiveJob::TestCase

  class DummyJob < ApplicationJob
    queue_as :default

    after_enqueue do |job|
      $dummy_job_enqueued = 1
    end

    def perform(*args)
      Rails.logger.debug("DummyJob executed")
    end
  end

  test "ensure_job_rescheduling" do
    dummy_job = DummyJob.new
    dummy_job.reset_job_warnings(1)
    sleep 3                                                                     # Age out the last job execution
    $dummy_job_enqueued = 0
    ApplicationJob.ensure_job_rescheduling
    assert_equal(1, $dummy_job_enqueued, log_on_failure("Job should have been enqueued"))
  end

end
