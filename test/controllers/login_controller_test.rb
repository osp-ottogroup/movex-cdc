require 'test_helper'
require 'user'

class LoginControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login existing user with email
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: Trixx::Application.config.trixx_db_password }
    assert_response :success

    # login  existing user with wrong password
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'wrong'}
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :unauthorized
    when 'SQLITE' then assert_response :success                                 # No password needed for SQLite
    end


    # login  existing user with db-user
    post login_do_logon_url, params: { email: Trixx::Application.config.trixx_db_user, password: Trixx::Application.config.trixx_db_password}
    assert_response :success

    # Non-existing user
    post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    assert_response :unauthorized

    # redundant db_user
    post login_do_logon_url, params: { email: 'double_db_user', password: 'hugo'}
    assert_response :unauthorized

  end

end
