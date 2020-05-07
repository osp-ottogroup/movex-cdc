class DbSchemasController < ApplicationController

  # GET /db_schemas
  # delivers all existing schemas
  def index
    @db_schemas = DbSchema.all

    render json: @db_schemas
  end

  # GET /db_schemas/remaining_schemas
  # delivers filtered list of schemas really owning tables
  # schemas already attached to the user are not listed again
  def remaining_schemas
    email = params.permit(:email)[:email]
    @db_schemas = DbSchema.remaining_schemas(email)

    render json: @db_schemas
  end

  # get /db_schemas/validate_user_name
  def validate_user_name
    user_name = params.permit(:user_name)[:user_name]
    if DbSchema.valid_schema_name?(user_name)
      render '', status: :ok
    else
      render '', status: :not_found
    end
  end

end
