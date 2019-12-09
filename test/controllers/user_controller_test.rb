require 'test_helper'

class UserControllerTest < ActionDispatch::IntegrationTest
  test "should get users" do
    get user_users_url
    assert_response :success
  end

end
