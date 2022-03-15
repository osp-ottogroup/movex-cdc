require 'json'

class ImportExportController < ApplicationController
  before_action :check_for_current_user_admin

  # get  '/import_export'
  def export
    out = export_schemas(Schema.all)
    render json: JSON.pretty_generate(out)
  end

  # get  '/import_export/:schema'
  def export_schema
    schemas = Schema.where(name: params[:schema])
    if schemas.count > 0
      out = export_schemas(schemas)
      render json: JSON.pretty_generate(out)
    else
      render json: {errors: ["Schema not found with name '#{params[:schema]}'"]}, status: :not_found
    end
  end

  # Importing one or all schemas
  # post '/import_export'
  def import
    logger.info('ImportExportController.import'){ 'Starting import of trigger configuration' }
    params.require([:users, :schemas])
    # TODO: Limit API for import of one single schema from the whole schemas JSON

    ActiveRecord::Base.transaction do
      ImportExportConfig.new.import_users(
        params[:users].map do |u|
          u.permit(ImportExportConfig.extract_column_names(User).map{|c| c.to_sym})  # permit all relevant column names without wildcard
        end
      )
    end

    ActiveRecord::Base.transaction do
      schema_hashes = params[:schemas].map{|s| s.permit!; s.to_h}
      # JSON.pretty_generate creates an empty line between [ and ] for empty arrays
      # if posted as request parameter Rails converts this empty line to on empty string element of the array
      # following function removes this empty string element from arrays
      check_array_for_empty_string_element(schema_hashes)
      ImportExportConfig.new.import_schemas(schema_hashes)
    end
  end

  private

  def export_schemas(schemas)
    out = Hash.new
    out['schemas'] = ImportExportConfig.new.export_schemas(schemas)
    out['users'] = ImportExportConfig.new.export_users
    out
  end

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
end