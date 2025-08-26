require 'test_helper'

class SystemValidationJobTest < ActiveJob::TestCase
  test "perform" do
    assert_nothing_raised do
      SystemValidationJob.new.perform
      SystemValidationJob.new.perform                                             # Must accept repeated execution
      sleep 1
      ThreadHandling.get_instance.shutdown_processing                             # don't wait until worker shutdown at end of tests at initializers/at_exit.rb
    end
  end
end
