require 'test_helper'

class InitializationJobTest < ActiveJob::TestCase
  test "startup" do
    # Remove exsting admin user created by fixture, should be recreated by next action
    admin = User.find_by_email 'admin'
    admin.destroy if admin

    InitializationJob.new.perform
    InitializationJob.new.perform                                               # Must except repeated execution
  end
end
