class UserController < ApplicationController
  # Controller for actions regarding user management (logon, user maintenance)

  # User-logon from GUI
  def do_logon
    email = prepare_param :email

    users = User.where email: email
    raise "No user found for email = '#{email}'" if users.count == 0
    raise "Multiple users found for email = '#{email}'" if users.count > 1
    user = users[0]

    render json: user
    # TODO: Define standard exception handler with JSON context
  end

end
