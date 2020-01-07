require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "create user" do
    User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf').save

    # Second user without db_name
    User.new(email: 'Hans.Dampf2@web.de', first_name: 'Hans', last_name: 'Dampf').save

    assert_raise(Exception, 'Duplicate should raise unique index violation') { User.new(email: 'Hans.Dampf@web.de', first_name: 'Hans', last_name: 'Dampf').save }

  end
end
