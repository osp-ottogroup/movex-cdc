require 'json'

class ImportExportController < ApplicationController
  before_action :check_for_current_user_admin

  # get  '/import_export/export'
  # exports all schemas or a single schema if param :schema is set
  def export
    schema_name = params[:schema]
    schema_name = nil if schema_name == ''

    if schema_name && !Schema.where(name: schema_name).first
      render json: {errors: ["Schema not found with name '#{params[:schema]}'"]}, status: :not_found
    else
      render json: JSON.pretty_generate(ImportExportConfig.new.export(single_schema_name: schema_name))
    end
  end

  # Import all schema definition according to selection in param :schema
  # post '/import_export/import'
  def import
    logger.info('ImportExportController.import'){ 'Starting import of trigger configuration' }
    params.require([:json_data])

    json_data = convert_json_data_param_to_h(params.permit![:json_data])
    raise "ImportExportController.import: JSON data should contain an 'schemas' array!" unless json_data['schemas']
    raise "ImportExportController.import: JSON data should contain an 'users' array!"   unless json_data['users']

    schema_list = normalize_schema_names(params[:schema])
    deactivate_missing_schemas = cast_boolean_param(params[:deactivate_missing_schemas])

    check_array_for_empty_string_element(json_data['schemas'])
    check_array_for_empty_string_element(json_data['users'])
    ImportExportConfig.new.import_schemas(
      json_data,
      schema_list,
      deactivate_missing_schemas
    )
  end

  # Import all users as they are incl. admin rights
  # post 'import_export/import_all_users'
  def import_all_users
    params.require([:json_data])
    ImportExportConfig.new.import_users(convert_json_data_param_to_h(params.permit![:json_data]))
  end

  private

  # JSON.pretty_generate creates an empty line between [ and ] for empty arrays
  # if posted as request parameter Rails converts this empty line to on empty string element of the array
  # This function removes this empty string element from arrays
  def check_array_for_empty_string_element(array)
    raise "check_array_for_empty_string_element should be called with parameter Array, but parameter is a '#{array.class}'" unless array.is_a? Array
    array.delete_if {|e| e == ''}
    # check elements of array in hierarchy
    array.each do |elem|
      raise "check_array_for_empty_string_element: Array elements should be of type Hash but element is a '#{elem.class}'" unless elem.is_a? Hash
      elem.each do |key, value|
        check_array_for_empty_string_element(value) if value.is_a? Array
      end
    end
  end

  # allow call by curl etc. without according application type
  def convert_json_data_param_to_h(params_data)
    case params_data.class.name
    when 'String' then JSON.parse(params_data)                        # http content type not application/json
    when 'ActionController::Parameters' then params_data.to_h         # http content type not application/json
    else raise "Unsupported class '#{params_data.class}' for parameter json_data"
    end
  end

  # Convert given schema names of different data types to an array of non-empty values
  # @param [String, Array<String>] a single name of a schema as string or a list of schema names as array
  # @return [Array<String>] list of non-empty and unique schema names as array
  def normalize_schema_names(schema_list)
    case
      when schema_list.nil?
        return []
      when schema_list.is_a?(Array)
        return schema_list.map{|schema_name| schema_name.to_s.strip }.reject(&:empty?).uniq
      else
        return [schema_list.to_s.strip].reject(&:empty?)
    end
  end

  # Converts given value to a boolean value based on predefined translations.
  # @param [Object] value The value to be converted to a boolean.
  # @return [Boolean] The boolean representation of the input value. If the value cannot be converted, returns false.
  def cast_boolean_param(value)
    case value
    when true, 'true', 'TRUE', 1, '1', 'on', 'ON', 'yes', 'YES', 'y', 'Y'
      true
    when false, 'false', 'FALSE', 0, '0', 'off', 'OFF', 'no', 'NO', 'n', 'N'
      false
    else
      false
    end
  end
end