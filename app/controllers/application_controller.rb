class ApplicationController < ActionController::API

  # Automatically protect every further controllers, exceptions are handled inside authorize_request
  before_action :authorize_request

  # protect_from_forgery with: :exception
  # respond_to :json

  NotAuthorized = Class.new(StandardError)
  rescue_from ApplicationController::NotAuthorized do |e|
    render json: { error: e.message }, status: :unauthorized
  end


  protected

  # authorize_request function has responsibility for authorizing user request.
  # first we need to get token in header with ‘Authorization’ as key.
  # with this token now we can decode and get the payload value.
  # in this application we define user_id in payload.
  # You should not include the user credentials data into payload because it will cause security issue, you can include data that needed to authorizing user.
  # When performing JsonWebToken.decode function, it will return JWT::DecodeError if there was an error like token was expired, token not valid, token missing etc.
  # After we got user_id from payload then we will try to find user by id and assign it into current_user variable,
  # If user not exist it will return ActiveRecord::RecordNotFound and it will render error message with http status unauthorized.
  @@authorize_exceptions = [{ controller: :login, action: :do_logon}]
  def authorize_request
    return if @@authorize_exceptions.include?(controller: controller_name.to_sym, action: action_name.to_sym)

    header = request.headers['Authorization']
    header = header.split(' ').last if header
    begin
      @decoded = JsonWebToken.decode(header)
      @current_user = User.find(@decoded[:user_id])
    rescue ActiveRecord::RecordNotFound => e
      render json: { error: e.message }, status: :unauthorized
    rescue JWT::DecodeError => e
      render json: { error: e.message }, status: :unauthorized
    end
  end

  # switch empty param string to nil
  def prepare_param(permitted_params, param_sym)
    retval = permitted_params[param_sym]
    retval = nil if retval == ''
    retval.strip! unless retval.nil? # Remove leading and trailing blanks
    retval
  end

  # Requires execution of 'authorize_request' in before_filter to fill @current_user
  def check_user_for_valid_schema_right(schema_id)
    raise ApplicationController::NotAuthorized, "Missing parameter schema_id for check of schema_rights for current user '#{@current_user.email}'" if schema_id.nil?
    schema_right = SchemaRight.find_by_user_id_and_schema_id(@current_user.id, schema_id)
    if schema_right.nil?
      schema = Schema.find_by_id schema_id
      raise ApplicationController::NotAuthorized, "Current user '#{@current_user.email}' has no right for schema '#{schema&.name}'"
    end
  end

end
