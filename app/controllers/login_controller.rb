# Controller for actions regarding user management (logon, user maintenance)
class LoginController < ApplicationController

  # load vuejs application
  def index
    render :file => 'public/index.html'
  end

  # User-logon from GUI
  # POST /login/do_logon
  # logon bei EMail/password or DB-User/password
  # DB-User requires that exactly one user is registered with this DB-user
  LOGON_DELAY_LIMIT = 5                                                         # Number of seconds between logons without delay
  @@last_call_time_do_logon = Time.now-100.seconds                              # ensure enough distance at startup
  def do_logon
    permitted = params.permit(:email, :password)
    email     = prepare_param permitted, :email
    password  = prepare_param permitted, :password
    error_msg = ''

    # prevent logon attacks
    if Time.now - LOGON_DELAY_LIMIT.seconds < @@last_call_time_do_logon   # suppress DOS attacks
      sleep_time = LOGON_DELAY_LIMIT - (Time.now - @@last_call_time_do_logon)
      Rails.logger.warn("Logon delayed by #{sleep_time} seconds due to subsequent logons within less than #{LOGON_DELAY_LIMIT} seconds for user = '#{email}'")
      sleep sleep_time unless Rails.env.test?
    end
    @@last_call_time_do_logon = Time.now

    user = User.find_by_email_case_insensitive email

    unless user                                                                 # try with db-user instead of email if email is not valid
      case User.count_by_db_user_case_insensitive email
      when 0 then
        Rails.logger.error "Logon request with not existing email/db-user='#{email}': #{request_log_attributes}"
        error_msg = "No user found for email / db-user = '#{email}'"
      when 1 then user = User.find_by_db_user_case_insensitive email
      else
        Rails.logger.error "Logon request with multiple registered db-user='#{email}': #{request_log_attributes}"
        error_msg = "Multiple users are registered for db-user = '#{email}'! Please login with mail address."
      end
    end

    if user
      auth_error = authenticate(user, password)
      if auth_error.nil?
        user.reset_failed_logons
        token_lifetime_hours = 24
        token = JsonWebToken.encode(
          {
            user_id: user.id,
            first_name: user.first_name,
            last_name: user.last_name,
            is_admin: user.yn_admin == 'Y',
            can_deploy: user.can_deploy_schemas?
          },
          token_lifetime_hours.hours.from_now
        )
        time = Time.now + token_lifetime_hours.hours.to_i
        render json: { token: token, exp: time.strftime("%m-%d-%Y %H:%M")}, status: :ok
      else
        Rails.logger.error "Authentication error '#{auth_error}' for '#{user.attributes}': #{request_log_attributes}"
        user.increment_failed_logons
        render json: { errors: [auth_error] }, status: :unauthorized
      end
    else
      render json: { errors: [error_msg] }, status: :unauthorized               # User does not exists for email or db_user
    end
  end

  # GET login/check_jwt
  # Check if JWT is valid for operation
  def check_jwt
    # ApplicationController.authorize_request raises Exception if JWT is not valid or aged out
    render json: { status: 'ok'}, status: :ok
  end


  @@last_call_time_release_info = Time.now-100.seconds                                       # ensure enough distance at startup
  # GET /login/release_info
  def release_info
    raise "Health check called too frequently" if Time.now - 1.seconds < @@last_call_time_release_info   # suppress DOS attacks
    @@last_call_time_release_info = Time.now

    begin
      release_info = File.read('/app/build_version')
    rescue Exception => e
      release_info = "No docker release info to read: #{e.class} #{e.message}"
    end
    render json: { release_info: release_info}, status: :ok
  end

  # GET /login/home_screen_info
  def home_screen_info
    render json: { home_screen_info: build_screen_info}, status: :ok
  end

  private

  # do authenticate against database, return nil for success or error message
  def authenticate(user, password)
    raise "Account is locked for '#{user.email}'" if user.yn_account_locked == 'Y'
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      db_config = Rails.configuration.database_configuration[Rails.env].clone
      db_config['username'] = user.db_user
      db_config['password'] = password

      db_config.symbolize_keys!

      connection = ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)  # raises connect errors if user or password is wrong
      connection.logoff
    when 'SQLITE' then
      raise "Wrong user/email #{user.email}"  if user.email != 'admin'
      raise 'wrong password'            if password != Trixx::Application.config.trixx_db_password
    end
    nil                                                                         # Indicator for successful connection
  rescue Exception => e
    e.message
  end

  # array with info-hashes to display at home screen { name: xxx, value: yyy }
  def build_screen_info
    info = []
    info << { name: 'Database URL',       value: Trixx::Application.config.trixx_db_url}
    info << { name: 'Kafka seed broker',  value: Trixx::Application.config.trixx_kafka_seed_broker}
    info << { name: 'Contact person', value: Trixx::Application.config.trixx_info_contact_person } if Trixx::Application.config.trixx_info_contact_person
    info.sort{|a,b| a[:name] <=> b[:name] }                                     # Show sorted list in GUI
  end
end
