require 'test_helper'

class HourlyJobTest < ActiveJob::TestCase
  test "perform" do
    assert_nothing_raised do
      HourlyJob.new.perform
      HourlyJob.new.perform                                             # Must accept repeated execution
    end
  end
end
