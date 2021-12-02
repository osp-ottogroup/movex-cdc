require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get users_url, headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get users_url, headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should create user" do
    assert_difference('User.count') do
      post users_url, headers: jwt_header(@jwt_admin_token), params: { user: {
          email: 'Hans.Dampf@ottogroup.com', db_user: Trixx::Application.config.db_user, first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N',
          schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.db_user}, yn_deployment_granted: 'N' }]
      } }, as: :json
    end
    assert_response 201

    post users_url, headers: jwt_header, params: { user: { email: 'Hans.Dampf@ottogroup.com', db_user: 'HANS', first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N'} }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

    User.where(email: 'Hans.Dampf@ottogroup.com').first.destroy                 # cleanup user table
  end

  test "should not create user with already existing email" do
    assert_difference('User.count') do
      post users_url, headers: jwt_header(@jwt_admin_token), params: { user: {
        email: 'Hans.Dampf@ottogroup.com', db_user: Trixx::Application.config.db_user, first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N',
        schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.db_user}, yn_deployment_granted: 'N' }]
      } }, as: :json
    end
    assert_response 201

    assert_no_difference('User.count') do
      post users_url, headers: jwt_header(@jwt_admin_token), params: { user: {
        email: 'Hans.Dampf@ottogroup.com', db_user: Trixx::Application.config.db_user, first_name: 'Hans', last_name: 'Dampf', yn_admin: 'N',
        schema_rights: [ {info: 'Info for right', schema: { name: Trixx::Application.config.db_user}, yn_deployment_granted: 'N' }]
      } }, as: :json
    end
    assert_response :unprocessable_entity

    User.where(email: 'Hans.Dampf@ottogroup.com').first.destroy                 # cleanup user table
  end

  test "should show user" do
    get user_url(peter_user), headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get user_url(peter_user), headers: jwt_header, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

  end

  test "should update user" do
    schema_right = SchemaRight.where(user_id: peter_user.id, schema_id: user_schema.id)[0]        # schema_right regularly already exists
    user = User.find(peter_user.id)
    patch user_url(user), headers: jwt_header(@jwt_admin_token), params: { user: { first_name: 'Peter',
                                                                                    schema_rights: [
                                                                                        {
                                                                                            info: 'Info for right',
                                                                                            schema: { name: Trixx::Application.config.db_user},
                                                                                            lock_version: schema_right&.lock_version,
                                                                                            yn_deployment_granted: 'N'
                                                                                        }
                                                                                    ],
                                                                                    lock_version: user.lock_version
    } }, as: :json
    assert_response 200

    patch user_url(peter_user), headers: jwt_header, params: { user: { first_name: 'Hugo' } }, as: :json
    assert_response :unauthorized, 'Access allowed to supervisor only'

    GlobalFixtures.restore_schema_rights
  end

  test "should destroy user" do
    user_to_delete = User.new(email: 'hans.dampf2@hugo.de', db_user: Trixx::Application.config.db_user, first_name: 'hans', last_name: 'dampf2')
    user_to_delete.save!

    assert_raise ActiveRecord::StaleObjectError, 'Should raise ActiveRecord::StaleObjectError' do
      delete user_url(user_to_delete), headers: jwt_header(@jwt_admin_token), params: { user: {lock_version: 42}}, as: :json
    end

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

  test "should have deployable schemas" do
    # using fixtures user(:one) and schema_rights(one)
    get deployable_schemas_user_url(peter_user), headers: jwt_header(@jwt_admin_token)
    assert_response :success
  end

  test "should not have deployable schemas" do
    new_sr = SchemaRight.new(user_id: sandro_user.id,
                    schema_id:  user_schema.id,
                    info:       'Info',
                    yn_deployment_granted: 'N'
    )
    new_sr.save!
    get deployable_schemas_user_url(sandro_user), headers: jwt_header(@jwt_admin_token)
    assert_response :success
    new_sr.destroy!
  end

end
