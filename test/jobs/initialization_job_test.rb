require 'test_helper'

class InitializationJobTest < ActiveJob::TestCase
  test "startup" do
    # Remove exsting admin user created by fixture, should be recreated by next action
    admin = User.where(email: 'admin').first
    if admin
      ActivityLog.delete(ActivityLog.where(user_id: admin.id).map{|a| a.id})    # Remove relation to allow delete of user
      admin.destroy!
    end

    assert_difference('User.count', 1, 'Should add new user admin') do
      InitializationJob.new.perform
    end
    InitializationJob.new.perform                                               # Must except repeated execution with existing user admin
  end
end
