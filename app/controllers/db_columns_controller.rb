class DbColumnsController < ApplicationController

  # GET /db_columns with parameter schema_name, table_name
  def index
    schema_name = params.require(:schema_name)
    table_name  = params.require(:table_name)

    @db_columns = DbColumn.all_by_table(schema_name, table_name)

    render json: @db_columns
  end

end
