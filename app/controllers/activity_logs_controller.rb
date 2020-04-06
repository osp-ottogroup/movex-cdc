class ActivityLogsController < ApplicationController

  # GET /activity_logs
  # get records according to filter parameters
  # optional parameters: user_id, schema_name, table_name, column_name
  def index
    optional_params = params.permit(:user_id, :schema_name, :table_name, :column_name)

    filter = {}
    filter[:user_id]      = optional_params[:user_id]     if optional_params[:user_id]
    filter[:schema_name]  = optional_params[:schema_name] if optional_params[:schema_name]
    filter[:table_name]   = optional_params[:table_name]  if optional_params[:table_name]
    filter[:column_name]  = optional_params[:column_name] if optional_params[:column_name]

    raise "At least one of optional filters should be used" if filter.count == 0

    @activity_logs = ActivityLog.where filter

    render json: @activity_logs
  end

  ALLOWED_LEVELS = ['debug', 'info', 'warn', 'error']

  # POST /activity_logs
  # Persist warning/error messages from frontend
  def create
    activity_log_params.require [:level, :user_id, :action]               # minimum set of values
    pars = activity_log_params.to_h

    raise "Parameter :level should contain one of #{ALLOWED_LEVELS}" unless ALLOWED_LEVELS.include?(pars['level'])

    user = User.find pars['user_id']
    message = "Frontend: Level='#{pars['level']}' User='#{user.email}' "
    message << "Schema='#{pars['schema_name']}' " if pars['schema_name']  && pars['schema_name']  != ''
    message << "Table='#{pars['table_name']}' "   if pars['table_name']   && pars['table_name']   != ''
    message << "Column='#{pars['column_name']}' " if pars['column_name']  && pars['column_name']  != ''
    message << ": #{pars['action']}"
    Rails.logger.send pars['level'], message

    pars['action'] = "Frontend #{pars['level']}: #{pars['action']}"
    pars.delete 'level'

    @activity_log = ActivityLog.new(pars)  # use params reduced by level
    if @activity_log.save
      render json: @activity_log, status: :created
    else
      render json: @activity_log.errors, status: :unprocessable_entity
    end
  end

  private
  # Only allow a trusted parameter "white list" through.
  def activity_log_params
    params.fetch(:activity_log, {}).permit(:level, :user_id, :schema_name, :table_name, :column_name, :action)
  end



end
