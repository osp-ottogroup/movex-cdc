# Controller for actions regarding user management (logon, user maintenance)
class LoginController < ApplicationController
  before_action :authorize_request, except: :do_logon

  # User-logon from GUI
  # POST /login/do_logon
  # logon bei EMail/password or DB-User/password
  # DB-User requires that exactly one user is registered with this DB-user
  def do_logon
    permitted = params.permit(:email, :password)
    email     = prepare_param permitted, :email
    password  = prepare_param permitted, :password
    error_msg = ''
    user = User.find_by_email email

    unless user                                                                 # try with db-user instead of email if email is not valid
      existing_users = User.where(db_user: email).count
      case existing_users
      when 0 then
        Rails.logger.error "Logon request with not existing email/db-user='#{email}': #{request_log_attributes}"
        error_msg = "No user found for email / db-user = '#{email}'"
      when 1 then user = User.find_by_db_user email
      else
        Rails.logger.error "Logon request with multiple registered db-user='#{email}': #{request_log_attributes}"
        error_msg = "Multiple users are registered for db-user = '#{email}'! Please login with mail address."
      end
    end

    if user
      auth_error = authenticate(user, password)
      if auth_error.nil?
        token_lifetime_hours = 24
        token = JsonWebToken.encode(
            {user_id: user.id},
            token_lifetime_hours.hours.from_now
        )
        time = Time.now + token_lifetime_hours.hours.to_i
        render json: { token: token, exp: time.strftime("%m-%d-%Y %H:%M")}, status: :ok
      else
        Rails.logger.error "Authentication error '#{auth_error}' for '#{user.attributes}': #{request_log_attributes}"
        render json: { error: auth_error }, status: :unauthorized
      end
    else
      render json: { error: error_msg }, status: :unauthorized
    end
  end

  private

  # do authenticate against database, return nil for success or error message
  def authenticate(user, password)
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      db_config = Rails.configuration.database_configuration[Rails.env].clone
      db_config['username'] = user.db_user
      db_config['password'] = password

      db_config.symbolize_keys!

      connection = ActiveRecord::ConnectionAdapters::OracleEnhanced::JDBCConnection.new(db_config)
      connection.logoff
    when 'SQLITE' then
      raise "Wrong user/email #{user.email}"  if user     != 'admin'
      raise 'wrong password'            if password != Trixx::Application.config.trixx_db_password
    end
    nil                                                                         # Indicator for successful connection
  rescue Exception => e
    e.message
  end
end
