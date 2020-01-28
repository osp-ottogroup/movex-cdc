class DbTablesController < ApplicationController

  # GET /db_tables with parameter schema_name
  def index
    schema_name = params.require(:schema_name)
    @db_tables = DbTable.all_by_schema(schema_name)

    render json: @db_tables
  end

end
