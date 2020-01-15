class DbSchemasController < ApplicationController
  # GET /db_schemas
  def index
    @db_schemas = DbSchema.all

    render json: @db_schemas
  end

end
