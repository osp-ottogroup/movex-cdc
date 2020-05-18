require 'test_helper'
require 'user'

class LoginControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login admin user with email
    post login_do_logon_url, params: { email: 'admin', password: Trixx::Application.config.trixx_db_password }
    assert_response :success

    # login existing user with email downcase
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.downcase, password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :success, 'Login with email in downcase should be possible'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # login existing user with email upcase
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.upcase, password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :success, 'Login with email in upcase should be possible'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    4.downto(0) do                                                              # account is locked after 5 failed logon tries
      # login  existing user with wrong password
      post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'wrong'}
      case Trixx::Application.config.trixx_db_type
      when 'ORACLE' then assert_response :unauthorized
      when 'SQLITE' then assert_response :unauthorized                            # Only 'admin' allowed for SQLite
      end
    end

    # login existing user with email upcase, account should be locked now
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.upcase, password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :unauthorized, 'Login with email in upcase should not be possible because account is locked now'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # login  existing user with db-user (admin) in downcase
    post login_do_logon_url, params: { email: Trixx::Application.config.trixx_db_user.downcase, password: Trixx::Application.config.trixx_db_password}
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :success, 'Login with DB password should be possible with downcase'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # login  existing user with db-user (admin) in upcase
    post login_do_logon_url, params: { email: Trixx::Application.config.trixx_db_user.upcase, password: Trixx::Application.config.trixx_db_password}
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then assert_response :success, 'Login with DB password should be possible with downcase'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # Non-existing user
    post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    assert_response :unauthorized, 'Non existing user should not be able to login'

    # redundant db_user
    post login_do_logon_url, params: { email: 'double_db_user', password: 'hugo'}
    assert_response :unauthorized, 'Redundant DB user should not used to login'

  end

  test "should get check_jwt" do
    get login_check_jwt_url, as: :json
    assert_response :unauthorized, 'No access should be possible without valid JWT'

    get login_check_jwt_url, headers: jwt_header, as: :json
    assert_response :success, 'Access should be possible with valid JWT'
  end

  test "should get release_info" do
    get login_release_info_url, as: :json
    assert_response :success, 'Access should be possible without valid JWT'
  end

end
