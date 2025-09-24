require 'test_helper'

class DailyJobTest < ActiveJob::TestCase
  test "perform" do
    assert_nothing_raised do
      DailyJob.new.perform
      DailyJob.new.perform                                             # Must accept repeated execution
    end
  end
end
