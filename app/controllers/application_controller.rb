class ApplicationController < ActionController::API
  # protect_from_forgery with: :exception
  # respond_to :json

  protected

  # switch empty param string to nil
  def prepare_param(param_sym)
    retval = params[param_sym]
    retval = nil if retval == ''
    retval.strip! unless retval.nil? # Remove leading and trailing blanks
    retval
  end
end
