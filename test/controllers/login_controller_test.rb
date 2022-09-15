require 'test_helper'
require 'user'

class LoginControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login admin user with email
    post login_do_logon_url, params: { email: 'admin', password: MovexCdc::Application.config.db_password }
    assert_response :success

    # login existing user with email downcase
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.downcase, password: MovexCdc::Application.config.db_victim_password }
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then assert_response :success, log_on_failure('Login with email in downcase should be possible')
    when 'SQLITE' then assert_response :unauthorized, log_on_failure('Only admin allowed for SQLite')
    end

    # login existing user with email upcase
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.upcase, password: MovexCdc::Application.config.db_victim_password }
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then assert_response :success, log_on_failure('Login with email in upcase should be possible')
    when 'SQLITE' then assert_response :unauthorized, log_on_failure('Only admin allowed for SQLite')
    end

    4.downto(0) do                                                              # account is locked after 5 failed logon tries
      # login  existing user with wrong password
      post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'wrong'}
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then assert_response :unauthorized
      when 'SQLITE' then assert_response :unauthorized                            # Only 'admin' allowed for SQLite
      end

      # Login with right password to prevent database account from beeing locked after x unsuccessful trials
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then
        db_config = Rails.configuration.database_configuration[Rails.env].clone
        db_config['username'] = MovexCdc::Application.config.db_victim_user
        db_config['password'] = MovexCdc::Application.config.db_victim_password
        db_config.symbolize_keys!
        Rails.logger.debug('LoginControllerTest.should post do_logon'){ "creating JDBCConnection with right credentials" }
        ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)
      end
    end

    # login existing user with email upcase, account should be locked now
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.upcase, password: MovexCdc::Application.config.db_victim_password }
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then assert_response :unauthorized, log_on_failure('Login with email in upcase should not be possible because account is locked now')
    when 'SQLITE' then assert_response :unauthorized, log_on_failure('Only admin allowed for SQLite')
    end

    # Unlock account for further use
    user = User.find_by_email_case_insensitive('Peter.Ramm@ottogroup.com')
    run_with_current_user { user.update(yn_account_locked: 'N') }

    # login  existing user with db-user (admin) in downcase
    post login_do_logon_url, params: { email: MovexCdc::Application.config.db_user.downcase, password: MovexCdc::Application.config.db_password}
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then assert_response :success, log_on_failure('Login with DB password should be possible with downcase')
    when 'SQLITE' then assert_response :unauthorized, log_on_failure('Only admin allowed for SQLite')
    end

    # login  existing user with db-user (admin) in upcase
    post login_do_logon_url, params: { email: MovexCdc::Application.config.db_user.upcase, password: MovexCdc::Application.config.db_password}
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then assert_response :success, log_on_failure('Login with DB password should be possible with upcase')
    when 'SQLITE' then assert_response :unauthorized, log_on_failure('Only admin allowed for SQLite')
    end

    # Non-existing user
    post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    assert_response :unauthorized, log_on_failure('Non existing user should not be able to login')

    # redundant db_user
    post login_do_logon_url, params: { email: 'double_db_user', password: 'hugo'}
    assert_response :unauthorized, log_on_failure('Redundant DB user should not used to login')

  end

  test "lock account after 5 attempts" do
    if MovexCdc::Application.config.db_type != 'SQLITE'
      org_value = MovexCdc::Application.config.max_failed_logons_before_account_locked
      MovexCdc::Application.config.max_failed_logons_before_account_locked = 3
      # try wrong password until account is locked for user 'admin'
      3.downto(1) do
        post login_do_logon_url, params: { email: MovexCdc::Application.config.db_user.downcase, password: 'wrong password'}
      end

      post login_do_logon_url, params: { email: MovexCdc::Application.config.db_user.downcase, password: MovexCdc::Application.config.db_password}
      assert_response :unauthorized, log_on_failure('Also the valid password should not function now')

      run_with_current_user { User.where(email: 'admin').first.update!(yn_account_locked: 'N') }

      post login_do_logon_url, params: { email: MovexCdc::Application.config.db_user.downcase, password: MovexCdc::Application.config.db_password}
      assert_response :success, log_on_failure('After unlock user logon should be possible again')
      MovexCdc::Application.config.max_failed_logons_before_account_locked = org_value # Restore original state
    end

  end

  test "should get check_jwt" do
    get login_check_jwt_url, as: :json
    assert_response :unauthorized, log_on_failure('No access should be possible without valid JWT')

    get login_check_jwt_url, headers: jwt_header, as: :json
    assert_response :success, log_on_failure('Access should be possible with valid JWT')
  end

  test "should get release_info" do
    get login_release_info_url, as: :json
    assert_response :success, log_on_failure('Access should be possible without valid JWT')
  end

end
