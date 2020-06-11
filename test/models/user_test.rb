require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "create user" do
    assert_difference('User.count') do
      User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: Trixx::Application.config.trixx_db_victim_user).save!
    end

    # Second user
    assert_difference('User.count') do
      User.new(email: 'Hans.Dampf2@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: Trixx::Application.config.trixx_db_victim_user).save!
    end

    assert_raise(Exception, 'Duplicate should raise unique index violation') { User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: Trixx::Application.config.trixx_db_victim_user).save! }
  end

  test "select user" do
    users = User.all
    assert(users.count > 0, 'Should return at least one user')
  end

end
