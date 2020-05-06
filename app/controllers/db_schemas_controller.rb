class DbSchemasController < ApplicationController

  # GET /db_schemas
  # delivers filtered list of schemas really owning tables
  # schemas already attached to the user are not listed again
  def index
    @db_schemas = DbSchema.remaining_schemas(@current_user)

    render json: @db_schemas
  end

end
