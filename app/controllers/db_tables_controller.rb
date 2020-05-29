class DbTablesController < ApplicationController

  # GET /db_tables with parameter schema_name
  def index
    schema_name = params.require(:schema_name)
    @db_tables = DbTable.all_by_schema(schema_name)

    render json: @db_tables
  end

  # GET /db_tables/remaining with parameter schema_id
  # list table names of schema not already observed by Trixx
  def remaining
    schema_id = params.require(:schema_id)
    @db_tables = DbTable.remaining_by_schema_id(schema_id)
    render json: @db_tables
  end


end
