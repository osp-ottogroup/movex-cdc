require 'test_helper'

class ApplicationJobTest < ActiveJob::TestCase

  class DummyJob < ApplicationJob
    queue_as :default

    after_enqueue do |job|
      $dummy_job_enqueued = 1
    end

    def perform(*args)
      Rails.logger.debug('DummyJob.perform'){ "DummyJob executed"}
    end
  end

end
