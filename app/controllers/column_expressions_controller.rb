class ColumnExpressionsController < ApplicationController
  before_action :set_column_expression, only: [:show, :update, :destroy]

  # GET /column_expressions
  def index
    table_id = params.require(:table_id)                                        # Should only list column_expressions of specific table
    table = Table.includes(:schema).find table_id
    Table.check_table_allowed_for_db_user(schema_name: table.schema.name, table_name: table.name)
    @column_expression = ColumnExpression.where table_id: table_id
    render json: @column_expression
  end

  # GET /column_expressions/1
  def show
    render json: @column_expression
  end

  # POST /column_expressions
  def create
    column_expression_params.require [:table_id, :operation, :sql]                   # minimum set of values
    @column_expression = ColumnExpression.new(column_expression_params)
    table = Table.find @column_expression.table_id
    Table.check_table_allowed_for_db_user(schema_name: table.schema.name, table_name: table.name)

    if @column_expression.save
      render json: @column_expression, status: :created, location: @column_expression
    else
      render json: { errors: @column_expression.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /column_expressions/1
  def update
    column_expression_params.require(:lock_version)    # Ensure that column lock_version is sent as param from client
    if @column_expression.update(column_expression_params)
      render json: @column_expression
    else
      render json: { errors: @column_expression.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /column_expressions/1
  def destroy
    @column_expression.lock_version = column_expression_params.require(:lock_version)    # Ensure that column lock_version is sent as param from client
    @column_expression.destroy!
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_column_expression
    @column_expression = ColumnExpression.find(params[:id])
    table = Table.find @column_expression.table_id
    Table.check_table_allowed_for_db_user(schema_name: table.schema.name, table_name: table.name)
  end

  # Only allow a trusted parameter "white list" through.
  def column_expression_params
    params.fetch(:column_expression, {}).permit(:table_id, :operation, :sql, :info, :lock_version)
  end
end
