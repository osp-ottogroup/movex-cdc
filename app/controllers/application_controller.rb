class ApplicationController < ActionController::API
  include ApplicationHelper

  # Automatically protect every further controllers, exceptions are handled inside authorize_request
  before_action :authorize_request                                              # ensures that processing is terminated after rendering an error
  around_action :around_action

  # protect_from_forgery with: :exception
  # respond_to :json

  NotAuthorized = Class.new(StandardError)
  rescue_from ApplicationController::NotAuthorized do |e|
    Rails.logger.error "Not authorized activity '#{e.message}' in request: #{request_log_attributes}"
    render json: { status:  :unauthorized, error: e.message }, status: :unauthorized
  end

  # Catch all remaining errors with exception content in response
  rescue_from Exception do |e|
    self.class.unset_current_user
    self.class.unset_current_client_ip_info
    ExceptionHelper.log_exception(e, 'ApplicationController.rescue_from', additional_msg: "Request: #{request_log_attributes}")
    render json: { status: :internal_server_error, error: e.message, error_class: e.class.name }, status: :internal_server_error
  end

  # get the user that is active only for the duration of a single request processing
  def self.current_user
    if Thread.current[:current_user]
      Thread.current[:current_user]
    else
      raise "ApplicationController.current_user: No current user set for thread #{Thread.current.object_id}"
    end
  end

  # get the client ip info that is active only for the duration of a single request processing
  def self.current_client_ip_info
    if Thread.current[:current_client_ip_info]
      Thread.current[:current_client_ip_info]
    else
      raise "ApplicationController.current_client_ip_info: No current client IP info set for thread #{Thread.current.object_id}"
    end
  end

  # Mark all actions in current thread with this user until it is unset at the end of request processing
  def self.set_current_user(current_user)
    unless Thread.current[:current_user].nil?
      Rails.logger.error("#{self.class}.set_current_user"){ "Current thread already contains a corresponding user with email='#{Thread.current[:current_user].email}', but should not" }
    end
    Rails.logger.debug('ApplicationController.set_current_user'){ "Set current user to #{current_user.email}#{" but previous user #{Thread.current[:current_user]}is still existing" unless Thread.current[:current_user].nil?}" }
    Thread.current[:current_user] = current_user
  end

  def self.set_current_client_ip_info(client_ip_info)
    unless Thread.current[:current_client_ip_info].nil?
      Rails.logger.error("#{self.class}.set_current_client_ip_info"){ "Current thread already contains a corresponding current_client_ip_info='#{Thread.current[:current_client_ip_info]}', but should not" }
    end
    Thread.current[:current_client_ip_info] = client_ip_info
  end


  # Remove user setting in current thread
  def self.unset_current_user
    Rails.logger.debug('ApplicationController.unset_current_user'){ "Unset current user from '#{(Thread.current[:current_user])&.email}'" }
    Thread.current[:current_user] = nil
  end

  def self.unset_current_client_ip_info
    Thread.current[:current_client_ip_info] = nil
  end

  protected

  # authorize_request function has responsibility for authorizing user request.
  # first we need to get token in header with ‘Authorization’ as key.
  # with this token now we can decode and get the payload value.
  # in this application we define user_id in payload.
  # You should not include the user credentials data into payload because it will cause security issue, you can include data that needed to authorizing user.
  # When performing JsonWebToken.decode function, it will return JWT::DecodeError if there was an error like token was expired, token not valid, token missing etc.
  # After we got user_id from payload then we will try to find user by id and assign it into current_user variable of current thread,
  # If user not exist it will return ActiveRecord::RecordNotFound and it will render error message with http status unauthorized.
  @@authorize_exceptions = [
    { controller: :login,         action: :do_logon},
    { controller: :login,         action: :index },
    { controller: :login,         action: :release_info },
    { controller: :health_check,  action: :index},
    { controller: :help,          action: :doc_html },
    { controller: :help,          action: :doc_pdf }
  ]

  # requests that do not need DB connection and do not need setting application info
  @@set_application_info_exceptions = [
    { controller: :login,         action: :release_info },
    { controller: :help,          action: :doc_html },
    { controller: :help,          action: :doc_pdf }
  ]

  # Terminate further processing if request is not authorized
  def authorize_request
    # register DB session only if DB is really needed for action
    # ensure that e.g. health_check also works if DB is down

    self.class.set_current_client_ip_info(client_ip_info)

    if @@set_application_info_exceptions.select{|e| e[:controller] == controller_name.to_sym && e[:action] == action_name.to_sym } == []
      # requires DB connection
      Database.verify_db_connection
      Database.set_application_info("#{controller_name}/#{action_name}")
    end

    if @@authorize_exceptions.select{|e| e[:controller] == controller_name.to_sym && e[:action] == action_name.to_sym} != []
      return
    end

    err_msg = validate_jwt
    unless err_msg.nil?
      unless controller_name == 'login' && action_name == 'check_jwt'
        Rails.logger.error('ApplicationController.authorize_request') { err_msg }
      end
      self.class.unset_current_user                                             # Ensure that there are no fragments in thread from previous call
      self.class.unset_current_client_ip_info                                   # Ensure that there are no fragments in thread from previous call
      render json: { errors: [err_msg] }, status: :unauthorized
    end
  end

  # Check if jwt of current request is valid
  # @return: nil if JWT is valid or error message
  def validate_jwt
    header = request.headers['Authorization']
    header = header.split(' ').last if header
    begin
      @decoded = JsonWebToken.decode(header)
      self.class.set_current_user(User.find(@decoded[:user_id]))
    rescue ActiveRecord::RecordNotFound => e
      return "Unauthorized request with valid token but not existing user: #{request_log_attributes}\n#{e.class} #{e.message}"
    rescue JWT::DecodeError => e
      return "Unauthorized request with invalid token: #{request_log_attributes}\n#{e.class} #{e.message}"
    end
    nil                                                                         # Mark JWT as valid
  end

  # Action is executed after successful execution of request
  def around_action
    yield                                                                       # process the controller action
  ensure                                                                        # ensure unsetting thread state even if request failed
    self.class.unset_current_user
    self.class.unset_current_client_ip_info
  end

  # switch empty param string to nil
  def prepare_param(permitted_params, param_sym)
    retval = permitted_params[param_sym]
    retval = nil if retval == ''
    retval.strip! unless retval.nil? # Remove leading and trailing blanks
    retval
  end

  # read clients IP address from http request
  # if nginx reverse proxy is used, you should have set these header entries:
  #       proxy_set_header X-Real-IP $remote_addr;
  #       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  #       proxy_set_header X-Forwarded-Proto $scheme;
  def client_ip_info
    Rails.logger.debug('ApplicationController.client_ip_info') { "HTTP_X_FORWARDED_FOR=#{request.env['HTTP_X_FORWARDED_FOR']}, HTTP_X_REAL_IP=#{request.env['HTTP_X_REAL_IP']}, remote IP=#{request.remote_ip}"}
    request.env['HTTP_X_FORWARDED_FOR'] || request.env['HTTP_X_REAL_IP']  || request.remote_ip
  end

  def request_log_attributes
    text = "controller='#{controller_name}' action='#{action_name}' client_ip='#{client_ip_info}'"
  end

  def check_for_current_user_admin
    if ApplicationController.current_user.yn_admin != 'Y'
      render json: { errors: ["Access denied! User #{self.class.current_user.email} isn't tagged as admin"] }, status: :unauthorized
    end
  end
end
