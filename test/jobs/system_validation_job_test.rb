require 'test_helper'

class SystemValidationJobTest < ActiveJob::TestCase
  test "perform" do
    SystemValidationJob.new.perform
    SystemValidationJob.new.perform                                               # Must except repeated execution
  end
end
