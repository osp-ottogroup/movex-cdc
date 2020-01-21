require 'test_helper'

class InitializationJobTest < ActiveJob::TestCase
  test "startup" do
    # Remove exsting admin user created by fixture, should be recreated by next action
    admin = User.find_by_email 'admin'
    admin.destroy if admin

    assert_difference('User.count', 1, 'Should add new user admin') do
      InitializationJob.new.perform
    end
    InitializationJob.new.perform                                               # Must except repeated execution with existing user admin
  end
end
