class DbTriggersController < ApplicationController

  # GET /triggers
  # List triggers for schema
  def index
    schema_id = params.require(:schema_id).to_i                                 # should only list tables of specific schema
    ApplicationController.current_user.check_user_for_valid_schema_right(schema_id)

    @triggers = DbTrigger.find_all_by_schema_id schema_id
    render json: @triggers
  end

  # GET /db_triggers/details
  # List details of one trigger
  def show
    params.require([:table_id, :trigger_name])
    table = Table.find params[:table_id]
    ApplicationController.current_user.check_user_for_valid_schema_right(table.schema_id)
    @trigger = DbTrigger.find_by_table_id_and_trigger_name(params[:table_id], params[:trigger_name])
    render json: @trigger
  end

  # POST /db_triggers/generate
  # Generate triggers for named schema
  # Parameter: schema_name, dry_run (true|false), table_id_list ( [] )
  # returns with status :ok { results: [ { schema_name:, successes: [], errors: []}, ... ]}
  # returns with status :internal_server_error { results: [ { schema_name:, successes: [], errors: []}, ... ], errors: []}
  def generate
    prepare_generate_params
    schema_name = params.require :schema_name

    schema = Schema.where(name: schema_name).first
    raise "Schema '#{schema_name}' is not configured for MOVEX Change Data Capture" if schema.nil?
    schema_right = ApplicationController.current_user.check_user_for_valid_schema_right(schema.id)
    raise "Current user '#{ApplicationController.current_user.email}' has no deployment right for schema '#{schema_name}" unless schema_right.yn_deployment_granted == 'Y'

    schema_result = DbTrigger.generate_schema_triggers(schema_id:     schema.id,
                                                       dry_run:       @dry_run,
                                                       table_id_list: @table_id_list
    )
    result = { results: [ schema_result.merge(schema_name: schema_name) ] }

    render json: result, status: :ok
  end

  # POST /db_triggers/generate_all
  # Generate triggers for all schema the user has rights for
  # Parameter: dry_run (true|false), table_id_list ( [] )
  # @return [Hash] with status :ok { results: [ { schema_name:, successes: [], errors: []}, ... ]}
  #   with status :internal_server_error { results: [ { schema_name:, successes: [], errors: []}, ... ], errors: []}
  def generate_all
    prepare_generate_params
    schema_rights = SchemaRight.where(user_id: ApplicationController.current_user.id, yn_deployment_granted: 'Y')
    if schema_rights.empty?
      render json: { errors: ["No schemas available for user '#{ApplicationController.current_user.email}'"] }, status: :not_found
    else
      results = []
      error_strings = []
      schema_rights.each do |sr|
        schema_result = DbTrigger.generate_schema_triggers(schema_id:     sr.schema_id,
                                                           dry_run:       @dry_run,
                                                           table_id_list: @table_id_list
        )
        error_strings.concat(structured_errors_to_string(schema_result[:errors], sr.schema.name)) if schema_result[:errors].count > 0
        schema_result[:schema_name] = sr.schema.name
        results << schema_result
      end
      result = { results: results}

      render json: result, status: :ok
    end
  end

  private
  # convert Array of structured errors to Array of Strings
  def structured_errors_to_string(errors, schema_name)
    errors.map do |error|
      "Table '#{schema_name}.#{error[:table_name]}', Trigger '#{error[:trigger_name]}'\n#{error[:exception_class]}: #{error[:exception_message]}"
    end
  end

  def prepare_generate_params
    @dry_run = params[:dry_run]
    @dry_run = @dry_run.strip.upcase == 'TRUE' if @dry_run.class == String      # curl and others encapsulates parameters in quotes
    @dry_run = false if @dry_run.nil?                                           # ensure boolean type

    @table_id_list = params[:table_id_list]
    @table_id_list = nil if @table_id_list == ''
    if @table_id_list
      raise "Parameter 'table_id_list' should be a table of IDs instead of #{@table_id_list.class}!" unless @table_id_list.instance_of? Array
      @table_id_list = @table_id_list.map{|i| i.to_i}
      raise "Non-integer content in parameter 'table_id_list'!" if @table_id_list.select{|i| i==0}.length > 0   # Contains IDs with result of to_i == 0
    end
  end
end
