require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get index" do
    get users_url, headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get users_url, headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should create user" do
    assert_difference('User.count') do
      post users_url, headers: jwt_header(@jwt_admin_token), params: { user: {
          email: 'Hans.Dampf@ottogroup.com', db_user: Trixx::Application.config.trixx_db_user, first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N',
          schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.trixx_db_user} }]
      } }, as: :json
    end
    assert_response 201

    post users_url, headers: jwt_header, params: { user: { email: 'Hans.Dampf@ottogroup.com', db_user: 'HANS', first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N'} }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should show user" do
    get user_url(@user), headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get user_url(@user), headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should update user" do
    schema_right = SchemaRight.where(user_id: @user.id, schema_id: 1)[0]        # schema_right regularly already exists

    patch user_url(@user), headers: jwt_header(@jwt_admin_token), params: { user: { email: 'Dummy@dummy.com',
                                                                                    schema_rights: [
                                                                                        {
                                                                                            info: 'Info for right',
                                                                                            schema: { name: Trixx::Application.config.trixx_db_user},
                                                                                            lock_version: schema_right&.lock_version
                                                                                        }
                                                                                    ],
                                                                                    lock_version: @user.lock_version
    } }, as: :json
    assert_response 200

    patch user_url(@user), headers: jwt_header, params: { user: { email: 'Dummy@dummy.com' } }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'
  end

  test "should destroy user" do
    ActivityLog.new(user_id: @user.id, action: 'At least one activity_logs record to prevent user from delete by foreign key').save!
    assert_difference('User.count', 0, 'User should be deactivated instead of deleted if foreign key supresses delete') do
      delete user_url(@user), headers: jwt_header(@jwt_admin_token), as: :json
    end
    assert_response 200


    # Remove objects that may cause foreign key error
    ActivityLog.all.each do |al|
      al.destroy!
    end

    assert_difference('User.count', -1) do
      delete user_url(@user), headers: jwt_header(@jwt_admin_token), as: :json
    end
    assert_response 204

    delete user_url(@user), headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end
end
