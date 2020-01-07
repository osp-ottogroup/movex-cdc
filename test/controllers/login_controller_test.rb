require 'test_helper'
require 'user'

class LoginControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login existing user
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'trixx'}
    assert_response :success

#    exc = assert_raise(Exception) do
#      post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
#    end
#    assert_match(/No user found/, exc.message, "Wrong exception content")

    # Non-existing user
    post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    assert_response :unauthorized
  end

end
