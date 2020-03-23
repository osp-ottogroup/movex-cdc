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

end
