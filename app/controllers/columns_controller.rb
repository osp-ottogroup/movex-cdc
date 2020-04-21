# generated by: rails generate scaffold_controller Schema
class ColumnsController < ApplicationController
  before_action :set_column, only: [:show, :update, :destroy]

  # GET /columns
  def index
    table_id = params.require(:table_id)                                        # Should only list columns of specific table
    table = Table.find table_id
    check_user_for_valid_schema_right(table.schema_id)

    @columns = Column.where table_id: table_id
    render json: @columns
  end

  # GET /columns/1
  def show
    render json: @column
  end

  # POST /columns
  def create
    column_params.require [:table_id]                                           # minimum set of values
    @column = Column.new(column_params)
    table = Table.find @column.table_id
    check_user_for_valid_schema_right(table.schema_id)

    if @column.save
      log_activity(
          schema_name:  table.schema.name,
          table_name:   table.name,
          column_name:  @column.name,
          action:       "column inserted: #{@column.attributes}"
      )
      render json: @column, status: :created, location: @column
    else
      render json: { errors: @column.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /columns/1
  def update
    if @column.update(column_params)
      log_activity(
          schema_name:  @column.table.schema.name,
          table_name:   @column.table.name,
          column_name:  @column.name,
          action:       "column updated: #{@column.attributes}"
      )
      render json: @column
    else
      render json: { errors: @column.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /columns/1
  def destroy
    @column.destroy
    log_activity(
        schema_name:  @column.table.schema.name,
        table_name:   @column.table.name,
        column_name:  @column.name,
        action:       "column deleted: #{@column.attributes}"
    )
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_column
      @column = Column.find(params[:id])
      table = Table.find @column.table_id
      check_user_for_valid_schema_right(table.schema_id)
    end

    # Only allow a trusted parameter "white list" through.
    def column_params
      params.fetch(:column, {}).permit(:table_id, :name, :info, :yn_log_insert, :yn_log_update, :yn_log_delete)
    end


end

