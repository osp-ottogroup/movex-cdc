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
          schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.trixx_db_user}, yn_deployment_granted: 'N' }]
      } }, as: :json
    end
    assert_response 201

    post users_url, headers: jwt_header, params: { user: { email: 'Hans.Dampf@ottogroup.com', db_user: 'HANS', first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N'} }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should not create user with already existing email" do
    assert_difference('User.count') do
      post users_url, headers: jwt_header(@jwt_admin_token), params: { user: {
        email: 'Hans.Dampf@ottogroup.com', db_user: Trixx::Application.config.trixx_db_user, first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N',
        schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.trixx_db_user}, yn_deployment_granted: 'N' }]
      } }, as: :json
    end
    assert_response 201

    assert_no_difference('User.count') do
      post users_url, headers: jwt_header(@jwt_admin_token), params: { user: {
        email: 'Hans.Dampf@ottogroup.com', db_user: Trixx::Application.config.trixx_db_user, first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N',
        schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.trixx_db_user}, yn_deployment_granted: 'N' }]
      } }, as: :json
    end
    assert_response :unprocessable_entity

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
                                                                                            lock_version: schema_right&.lock_version,
                                                                                            yn_deployment_granted: 'N'
                                                                                        }
                                                                                    ],
                                                                                    lock_version: @user.lock_version
    } }, as: :json
    assert_response 200

    patch user_url(@user), headers: jwt_header, params: { user: { email: 'Dummy@dummy.com' } }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'
  end

  test "should destroy user" do
    user_to_delete = User.new(email: 'hans.dampf2@hugo.de', db_user: Trixx::Application.config.trixx_db_user, first_name: 'hans', last_name: 'dampf2')
    user_to_delete.save!

    ActivityLog.new(user_id: user_to_delete.id, action: 'At least one activity_logs record to prevent user from delete by foreign key').save!

    assert_difference('User.count', 0, 'User should be deactivated instead of deleted if foreign key supresses delete') do
      delete user_url(user_to_delete), headers: jwt_header(@jwt_admin_token), params: { user: user_to_delete.attributes}, as: :json
    end
    assert_response 204

    # Remove objects that may cause foreign key error
    ActivityLog.where(user_id: user_to_delete.id).each do |al|
      al.destroy!
    end

    user_to_delete = User.find user_to_delete.id                                # ensure record has correct lock_version after above update
    assert_difference('User.count', -1) do
      delete user_url(user_to_delete), headers: jwt_header(@jwt_admin_token), params: { user: user_to_delete.attributes}, as: :json
    end
    assert_response 204

    delete user_url(user_to_delete), headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should not destroy user" do                                             # separate test because connect requires existence of user :one
    assert_raise ActiveRecord::StaleObjectError, 'Should raise ActiveRecord::StaleObjectError' do
      delete user_url(@user), headers: jwt_header(@jwt_admin_token), params: { user: {lock_version: 42}}, as: :json
    end
  end

  test "should have deployable schemas" do
    # using fixtures user(:one) and schema_rights(one)
    get deployable_schemas_user_url(@user), headers: jwt_header(@jwt_admin_token)
    assert_response :success
  end

  test "should not have deployable schemas" do
    SchemaRight.new(user_id: users(:two).id, schema_id: schemas(:one).id, info: 'Info', yn_deployment_granted: 'N').save!
    get deployable_schemas_user_url(@user), headers: jwt_header(@jwt_admin_token)
    assert_response :success
  end

end
