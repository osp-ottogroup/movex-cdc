require 'test_helper'
require 'user'

class LoginControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login admin user with email
    post login_do_logon_url, params: { email: 'admin', password: Trixx::Application.config.trixx_db_password }
    assert_response :success

    # login existing user with email
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :success
    when 'SQLITE' then assert_response :unauthorized                            # Only 'admin' allowed for SQLite
    end

    # login  existing user with wrong password
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'wrong'}
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :unauthorized
    when 'SQLITE' then assert_response :unauthorized                            # Only 'admin' allowed for SQLite
    end


    # login  existing user with db-user (admin)
    post login_do_logon_url, params: { email: Trixx::Application.config.trixx_db_user, password: Trixx::Application.config.trixx_db_password}
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :success
    when 'SQLITE' then assert_response :unauthorized                            # Only 'admin' allowed for SQLite
    end

    # Non-existing user
    post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    assert_response :unauthorized

    # redundant db_user
    post login_do_logon_url, params: { email: 'double_db_user', password: 'hugo'}
    assert_response :unauthorized

  end

end
