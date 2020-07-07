class UsersController < ApplicationController
  before_action :check_for_current_user_admin
  before_action :set_user, only: [:show, :update, :destroy]

  # GET /users
  def index
    @users = User.all.order(:last_name, :first_name)

    render json: @users, include: { schema_rights: {include: :schema} }
  end

  # GET /users/1
  def show
    render json: @user, include: { schema_rights: {include: :schema} }
  end

  # POST /users
  def create
    users = User.where email: user_params[:email]
    if users.length > 0 && user[0].yn_hidden == 'Y'
      @user = users[0]
      save_result = @user.update(user_params.to_h.merge({yn_account_locked: 'N', yn_hidden: 'N'}))    # mark visible for GUI and unlocked
    else
      @user = User.new(user_params)
      save_result = @user.save
    end

    if save_result
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
    user_params.require(:lock_version)    # Ensure that column lock_version is sent as param from client

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
    @user.lock_version = user_params.require(:lock_version)    # Ensure that column lock_version is sent as param from client
    if @user.destroy == :destroyed
      log_activity(action: "user deleted: #{@user.attributes}")
    else
      log_activity(action: "user set hidden: #{@user.attributes}")
    end
    # always return status = 204 No Content
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def user_params
      params.fetch(:user, {}).permit(:email, :db_user, :first_name, :last_name, :yn_admin, :yn_account_locked, :lock_version)
    end

    def schema_rights_params
      params.fetch(:user, {}).permit( [schema_rights: [:info, {schema: :name }, :lock_version] ] )[:schema_rights]
    end
end
