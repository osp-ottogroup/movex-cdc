class UsersController < ApplicationController
  before_action :check_for_current_user_admin
  before_action :set_user, only: [:show, :update, :destroy]

  # GET /users
  def index
    @users = User.all

    render json: @users, include: { schema_rights: {include: :schema} }
  end

  # GET /users/1
  def show
    render json: @user, include: { schema_rights: {include: :schema} }
  end

  # POST /users
  def create
    @user = User.new(user_params)

    if  @user.save
      SchemaRight.process_user_request(@user, schema_rights_params)
      log_activity(
          action:       "user inserted: #{@user.attributes}"
      )
      render json: @user, include: { schema_rights: {include: :schema} }, status: :created, location: @user
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /users/1
  def update
    if @user.update(user_params)
      SchemaRight.process_user_request(@user, schema_rights_params)
      log_activity(
          action:       "user updated: #{@user.attributes}"
      )
      render json: @user, include: { schema_rights: {include: :schema} }
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /users/1
  def destroy
    @user.destroy
    log_activity(
        action:       "user deleted: #{@user.attributes}"
    )
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def user_params
      params.fetch(:user, {}).permit(:email, :db_user, :first_name, :last_name, :yn_admin)
    end

    def schema_rights_params
      params.fetch(:user, {}).permit( [schema_rights: [:info, {schema: :name }] ] )[:schema_rights]
    end
end
