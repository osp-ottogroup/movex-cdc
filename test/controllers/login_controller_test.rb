require 'test_helper'
require 'user'

class LoginControllerTest < ActionDispatch::IntegrationTest

  test "should post do_logon" do
    # login admin user with email
    post login_do_logon_url, params: { email: 'admin', password: Trixx::Application.config.db_password }
    assert_response :success

    # login existing user with email downcase
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.downcase, password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.db_type
    when 'ORACLE' then assert_response :success, 'Login with email in downcase should be possible'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # login existing user with email upcase
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.upcase, password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.db_type
    when 'ORACLE' then assert_response :success, 'Login with email in upcase should be possible'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    4.downto(0) do                                                              # account is locked after 5 failed logon tries
      # login  existing user with wrong password
      post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com', password: 'wrong'}
      case Trixx::Application.config.db_type
      when 'ORACLE' then assert_response :unauthorized
      when 'SQLITE' then assert_response :unauthorized                            # Only 'admin' allowed for SQLite
      end

      # Login with right password to prevent database account from beeing locked after x unsuccessful trials
      case Trixx::Application.config.db_type
      when 'ORACLE' then
        db_config = Rails.configuration.database_configuration[Rails.env].clone
        db_config['username'] = Trixx::Application.config.trixx_db_victim_user
        db_config['password'] = Trixx::Application.config.trixx_db_victim_password
        db_config.symbolize_keys!
        Rails.logger.debug "LoginControllerTest.should post do_logon: creating JDBCConnection with right credentials"
        ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)
      end
    end

    # login existing user with email upcase, account should be locked now
    post login_do_logon_url, params: { email: 'Peter.Ramm@ottogroup.com'.upcase, password: Trixx::Application.config.trixx_db_victim_password }
    case Trixx::Application.config.db_type
    when 'ORACLE' then assert_response :unauthorized, 'Login with email in upcase should not be possible because account is locked now'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # Unlock account for further use
    user = User.find_by_email_case_insensitive('Peter.Ramm@ottogroup.com')
    user.yn_account_locked = 'N'
    user.save!

    # login  existing user with db-user (admin) in downcase
    post login_do_logon_url, params: { email: Trixx::Application.config.db_user.downcase, password: Trixx::Application.config.db_password}
    case Trixx::Application.config.db_type
    when 'ORACLE' then assert_response :success, 'Login with DB password should be possible with downcase'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # login  existing user with db-user (admin) in upcase
    post login_do_logon_url, params: { email: Trixx::Application.config.db_user.upcase, password: Trixx::Application.config.db_password}
    case Trixx::Application.config.db_type
    when 'ORACLE' then assert_response :success, 'Login with DB password should be possible with upcase'
    when 'SQLITE' then assert_response :unauthorized, 'Only admin allowed for SQLite'
    end

    # Non-existing user
    post login_do_logon_url, params: { email: 'Hugo@ottogroup.com', password: 'hugo'}
    assert_response :unauthorized, 'Non existing user should not be able to login'

    # redundant db_user
    post login_do_logon_url, params: { email: 'double_db_user', password: 'hugo'}
    assert_response :unauthorized, 'Redundant DB user should not used to login'

  end

  test "lock account after 5 attempts" do
    if Trixx::Application.config.db_type != 'SQLITE'
      # try wrong password until account is locked for user 'admin'
      3.downto(1) do
        post login_do_logon_url, params: { email: Trixx::Application.config.db_user.downcase, password: 'wrong password'}
      end

      post login_do_logon_url, params: { email: Trixx::Application.config.db_user.downcase, password: Trixx::Application.config.db_password}
      assert_response :unauthorized, 'Also the valid password should not function now'

      User.where(email: 'admin').first.update!(yn_account_locked: 'N')

      post login_do_logon_url, params: { email: Trixx::Application.config.db_user.downcase, password: Trixx::Application.config.db_password}
      assert_response :success, 'After unlock user logon should be possible again'
    end

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
