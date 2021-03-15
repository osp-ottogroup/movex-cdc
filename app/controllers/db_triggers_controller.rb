class DbTriggersController < ApplicationController

  # GET /triggers
  # List triggers for schema
  def index
    schema_id = params.require(:schema_id).to_i                                 # should only list tables of specific schema
    @current_user.check_user_for_valid_schema_right(schema_id)

    @triggers = DbTrigger.find_all_by_schema_id schema_id
    render json: @triggers
  end

  # GET /db_triggers/details
  # List details of one trigger
  def show
    params.require([:table_id, :trigger_name])
    table = Table.find params[:table_id]
    @current_user.check_user_for_valid_schema_right(table.schema_id)
    @trigger = DbTrigger.find_by_table_id_and_trigger_name(params[:table_id], params[:trigger_name])
    render json: @trigger
  end

  # POST /db_triggers/generate
  # Generate triggers for named schema
  # Parameter: schema_name, dry_run (true|false), table_id_list ( [] )
  # returns with status :ok { results: [ { schema_name:, successes: [], errors: []}, ... ]}
  # returns with status :internal_server_error { results: [ { schema_name:, successes: [], errors: []}, ... ], errors: []}
  def generate
    schema_name = params.require :schema_name
    dry_run = params[:dry_run]&.downcase == 'true'
    schema = Schema.where(name: schema_name).first
    raise "Schema '#{schema_name}' is not configured for TriXX" if schema.nil?
    schema_right = @current_user.check_user_for_valid_schema_right(schema.id)
    raise "Current user '#{@current_user.email}' has no deployment right for schema '#{schema_name}" unless schema_right.yn_deployment_granted == 'Y'

    schema_result = DbTrigger.generate_schema_triggers(schema_id:     schema.id,
                                                       user_options:  { user_id: @current_user.id, client_ip_info: client_ip_info},
                                                       dry_run:       dry_run
    )
    result = { results: [ schema_result.merge(schema_name: schema_name) ] }

    if schema_result[:errors].count == 0
      render json: result, status: :ok
    else
      result[:errors] = structured_errors_to_string(schema_result[:errors], schema_name)
      render json: result, status: :internal_server_error
    end
  end

  # POST /db_triggers/generate_all
  # Generate triggers for all schema the user has rights for
  # Parameter: dry_run (true|false), table_id_list ( [] )
  # returns with status :ok { results: [ { schema_name:, successes: [], errors: []}, ... ]}
  # returns with status :internal_server_error { results: [ { schema_name:, successes: [], errors: []}, ... ], errors: []}
  def generate_all
    dry_run = params[:dry_run]&.downcase == 'true'
    schema_rights = SchemaRight.where(user_id: @current_user.id, yn_deployment_granted: 'Y')
    if schema_rights.empty?
      render json: { errors: ["No schemas available for user '#{@current_user.email}'"] }, status: :not_found
    else
      results = []
      error_strings = []
      schema_rights.each do |sr|
        schema_result = DbTrigger.generate_schema_triggers(schema_id:     sr.schema_id,
                                                           user_options:  { user_id: @current_user.id, client_ip_info: client_ip_info },
                                                           dry_run:       dry_run
        )
        error_strings.concat(structured_errors_to_string(schema_result[:errors], sr.schema.name)) if schema_result[:errors].count > 0
        schema_result[:schema_name] = sr.schema.name
        results << schema_result
      end
      result = { results: results}
      if error_strings.count == 0
        render json: result, status: :ok
      else
        result[:errors] = error_strings
        render json: result, status: :internal_server_error
      end
    end
  end

  private
  # convert Array of structured errors to Array of Strings
  def structured_errors_to_string(errors, schema_name)
    errors.map do |error|
      "Table '#{schema_name}.#{error[:table_name]}', Trigger '#{error[:trigger_name]}'\n#{error[:exception_class]}: #{error[:exception_message]}"
    end
  end
end
