require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "create user" do
    User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf').save

    # Second user without db_name
    User.new(email: 'Hans.Dampf2@web.de', first_name: 'Hans', last_name: 'Dampf').save

    assert_raise(Exception, 'Duplicate should raise unique index violation') { User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf').save }

    user = User.new(email: 'DowncaseTest@web.de', first_name: 'Hans', last_name: 'Dampf', db_user: 'HUGO')
    user.save
    assert_equal('hugo', user.db_user, 'db_user should be converted to lower case')

  end

  test "select user" do
    users = User.all
    assert(users.count > 0, 'Should return at least one user')
  end

end
