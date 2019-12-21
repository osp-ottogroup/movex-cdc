require 'test_helper'
require 'user'

class UserControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login existing user
    post user_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'trixx'}
    assert_response :success

    exc = assert_raise(Exception) do
      post user_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    end
    assert_match(/No user found/, exc.message, "Wrong exception content")
  end

end
