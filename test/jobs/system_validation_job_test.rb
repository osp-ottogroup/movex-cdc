require 'test_helper'

class SystemValidationJobTest < ActiveJob::TestCase
  test "perform" do
    SystemValidationJob.new.perform
    SystemValidationJob.new.perform                                               # Must except repeated execution
    # shutdown threads is executed at end of test run by initializers/at_exit.rb
  end
end
