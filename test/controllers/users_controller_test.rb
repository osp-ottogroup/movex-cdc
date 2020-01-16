require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get index" do
    get users_url, headers: jwt_admin_header, as: :json
    assert_response :success

    get users_url, headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should create user" do
    assert_difference('User.count') do
      post users_url, headers: jwt_admin_header, params: { user: { email: 'Hans.Dampf@ottogroup.com', db_user: 'HANS', first_name: 'Hans', last_name: 'Dampf'} }, as: :json
    end
    assert_response 201

    post users_url, headers: jwt_header, params: { user: { email: 'Hans.Dampf@ottogroup.com', db_user: 'HANS', first_name: 'Hans', last_name: 'Dampf'} }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should show user" do
    get user_url(@user), headers: jwt_admin_header, as: :json
    assert_response :success

    get user_url(@user), headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should update user" do
    patch user_url(@user), headers: jwt_admin_header, params: { user: { email: 'Dummy@dummy.com' } }, as: :json
    assert_response 200

    patch user_url(@user), headers: jwt_header, params: { user: { email: 'Dummy@dummy.com' } }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'
  end

  test "should destroy user" do
    assert_difference('User.count', -1) do
      delete user_url(@user), headers: jwt_admin_header, as: :json
    end
    assert_response 204

    delete user_url(@user), headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end
end
