class TriggersController < ApplicationController

  # GET /triggers
  # List triggers for schema
  def index
    schema_id = params.require(:schema_id)                                      # should only list tables of specific schema
    check_user_for_valid_schema_right(schema_id)

    @triggers = Trigger.where schema_id: schema_id
    render json: @triggers
  end

  # GET /triggers/details
  # List details of one trigger
  def show
    params.require([:table_id, :trigger_name])
    table = Table.find params[:table_id]
    check_user_for_valid_schema_right(table.schema_id)
    @trigger = Trigger.find_by_table_id_and_trigger_name(params[:table_id], params[:trigger_name])
    render json: @trigger
  end

  # POST /triggers/generate_triggers
  # Generate triggers for named schema
  def generate
    schema_name = params.require([:schema_name])
    schema = Schema.find_by_name schema_name
    raise "Schema '#{schema_name}' is not configured for TriXX" if schema.nil?
    check_user_for_valid_schema_right(schema.id)

  end

end
