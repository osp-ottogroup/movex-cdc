# Controller for actions regarding user management (logon, user maintenance)
class LoginController < ApplicationController
  before_action :authorize_request, except: :do_logon

  # User-logon from GUI
  # POST /login/do_logon
  def do_logon
    email     = prepare_param :email
    password  = prepare_param :password

    user = User.find_by_email email
    if user
      auth_error = authenticate(password)
      if auth_error.nil?
        token_lifetime_hours = 24
        token = JsonWebToken.encode({user_id: user.id}, token_lifetime_hours.hours.from_now)
        time = Time.now + token_lifetime_hours.hours.to_i
        render json: { token: token, exp: time.strftime("%m-%d-%Y %H:%M")}, status: :ok
      else
        render json: { error: auth_error }, status: :unauthorized
      end
    else
      render json: { error: "No user found for email = '#{email}'" }, status: :unauthorized
    end
  end

  private

  # do authenticate against database, return nil for success or error message
  def authenticate(password)
    # TODO: authenticate against database
  end
end
