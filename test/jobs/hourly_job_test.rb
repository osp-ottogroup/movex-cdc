require 'test_helper'

class HourlyJobTest < ActiveJob::TestCase
  test "perform" do
    HourlyJob.new.perform
    HourlyJob.new.perform                                             # Must accept repeated execution
  end
end
