class DbTriggersController < ApplicationController

  # GET /triggers
  # List triggers for schema
  def index
    schema_id = params.require(:schema_id).to_i                                 # should only list tables of specific schema
    check_user_for_valid_schema_right(schema_id)

    @triggers = DbTrigger.find_all_by_schema_id schema_id
    render json: @triggers
  end

  # GET /db_triggers/details
  # List details of one trigger
  def show
    params.require([:table_id, :trigger_name])
    table = Table.find params[:table_id]
    check_user_for_valid_schema_right(table.schema_id)
    @trigger = DbTrigger.find_by_table_id_and_trigger_name(params[:table_id], params[:trigger_name])
    render json: @trigger
  end

  # POST /db_triggers/generate
  # Generate triggers for named schema
  def generate
    schema_name = params.require :schema_name
    schema = Schema.find_by_name schema_name
    raise "Schema '#{schema_name}' is not configured for TriXX" if schema.nil?
    check_user_for_valid_schema_right(schema.id)

    result = DbTrigger.generate_triggers(schema.id)
    render json: result, status: result[:errors].count == 0 ? :ok : :internal_server_error
  end

  # POST /db_triggers/generate_all
  # Generate triggers for all schema the user has rights for
  def generate_all
    schema_rights = SchemaRight.where(user_id: @current_user.id)
    if schema_rights.empty?
      render json: { errors: ["No schemas available for user '#{@current_user.email}'"] }, status: :unauthorized
    else
      result = []
      status = :ok
      schema_rights.each do |sr|
        schema_result = DbTrigger.generate_triggers(sr.schema_id)
        status = :internal_server_error if schema_result[:errors].count > 0
        schema_result[:schema_name] = sr.schema.name
        result << schema_result
      end
      render json: result, status: status
    end
  end

end
