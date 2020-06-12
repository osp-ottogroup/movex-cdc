class DbSchemasController < ApplicationController

  # GET /db_schemas
  # delivers all existing schemas
  def index
    @db_schemas = DbSchema.all
    render json: @db_schemas
  end

  # GET /db_schemas/authorizable_schemas
  # delivers filtered list of schemas where the current user has read grants on tables
  # schemas already attached to the user are not listed again
  def authorizable_schemas
    permitted_params = params.permit(:email, :db_user)
    @db_schemas = DbSchema.authorizable_schemas(permitted_params[:email], permitted_params[:db_user])

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
