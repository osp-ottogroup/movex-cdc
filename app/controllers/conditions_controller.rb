class ConditionsController < ApplicationController
  before_action :set_condition, only: [:show, :update, :destroy]

  # GET /conditions
  def index
    table_id = params.require(:table_id)                                        # Should only list conditions of specific table
    table = Table.find table_id
    Table.check_table_allowed_for_db_user(current_user: @current_user, schema_name: table.schema.name, table_name: table.name)
    @conditions = Condition.where table_id: table_id
    render json: @conditions
  end

  # GET /conditions/1
  def show
    render json: @condition
  end

  # POST /conditions
  def create
    condition_params.require [:table_id, :operation, :filter]                   # minimum set of values
    @condition = Condition.new(condition_params)
    table = Table.find @condition.table_id
    Table.check_table_allowed_for_db_user(current_user: @current_user, schema_name: table.schema.name, table_name: table.name)

    if @condition.save
      log_activity(
          schema_name:  table.schema.name,
          table_name:   table.name,
          action:       "condition inserted: #{@condition.attributes}"
      )
      render json: @condition, status: :created, location: @condition
    else
      render json: { errors: @condition.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /conditions/1
  def update
    condition_params.require(:lock_version)    # Ensure that column lock_version is sent as param from client
    if @condition.update(condition_params)
      log_activity(
          schema_name:  @condition.table.schema.name,
          table_name:   @condition.table.name,
          action:       "condition updated: #{@condition.attributes}"
      )
      render json: @condition
    else
      render json: { errors: @condition.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /conditions/1
  def destroy
    @condition.lock_version = condition_params.require(:lock_version)    # Ensure that column lock_version is sent as param from client
    @condition.destroy!
    log_activity(
        schema_name:  @condition.table.schema.name,
        table_name:   @condition.table.name,
        action:       "condition deleted: #{@condition.attributes}"
    )
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_condition
      @condition = Condition.find(params[:id])
      table = Table.find @condition.table_id
      Table.check_table_allowed_for_db_user(current_user: @current_user, schema_name: table.schema.name, table_name: table.name)
    end

    # Only allow a trusted parameter "white list" through.
    def condition_params
      params.fetch(:condition, {}).permit(:table_id, :operation, :filter, :lock_version)
    end
end
