class UsersController < ApplicationController
  before_action :authenticate
  before_action :set_user, only: [:show, :update, :destroy]

  # GET /users
  def index
    @users = User.all

    render json: @users
  end

  # GET /users/1
  def show
    render json: @user
  end

  # POST /users
  def create
    @user = User.new(user_params)

    if @user.save
      log_activity(
          action:       "user inserted: #{@user.attributes}"
      )
      render json: @user, status: :created, location: @user
    else
      render json: @user.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /users/1
  def update
    if @user.update(user_params)
      log_activity(
          action:       "user updated: #{@user.attributes}"
      )
      render json: @user
    else
      render json: @user.errors, status: :unprocessable_entity
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

  def authenticate
    if @current_user.email != 'admin'
      render json: { errors: "Access denied! User #{@current_user.email} isn't supervisor" }, status: :unauthorized
    end

  end

    # Only allow a trusted parameter "white list" through.
    def user_params
      params.fetch(:user, {}).permit(:email, :db_user, :first_name, :last_name)
    end
end
