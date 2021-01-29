require 'test_helper'

class DailyJobTest < ActiveJob::TestCase
  test "perform" do
    DailyJob.new.perform
    DailyJob.new.perform                                             # Must accept repeated execution
  end
end
