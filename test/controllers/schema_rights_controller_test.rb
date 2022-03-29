require 'test_helper'

class SchemaRightsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @schema_right = SchemaRight.where(user_id: peter_user.id,
                                      schema_id: user_schema.id
    ).first
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/schema_rights?user_id=#{peter_user.id}", headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get "/schema_rights?schema_id=#{user_schema.id}", headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get "/schema_rights?user_id=#{peter_user.id}", headers: jwt_header, as: :json
    assert_response :unauthorized, log_on_failure('Should not get access without admin role')
  end

  test "should create schema_right" do
    assert_difference('SchemaRight.count') do
      post schema_rights_url, headers: jwt_header(@jwt_admin_token), params: { schema_right: { user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info' } }, as: :json
    end
    assert_response 201

    post schema_rights_url, headers: jwt_header, params: { schema_right: { user_id: sandro_user.id, schema_id: user_schema.id, info: 'Info'  } }, as: :json
    assert_response :unauthorized, log_on_failure('Should not get access without admin role')

    run_with_current_user { SchemaRight.where(user_id: sandro_user.id, schema_id: user_schema.id).first.destroy! } # Restore original state
  end

  test "should show schema_right" do
    get schema_right_url(@schema_right), headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success

    get schema_right_url(@schema_right), headers: jwt_header, as: :json
    assert_response :unauthorized, log_on_failure('Should not get access without admin role')
  end

  test "should update schema_right" do
    patch schema_right_url(@schema_right), headers: jwt_header(@jwt_admin_token), params: { schema_right: { info: 'changed info', lock_version: @schema_right.lock_version } }, as: :json
    assert_response 200

    patch schema_right_url(@schema_right), headers: jwt_header, params: { schema_right: {  } }, as: :json
    assert_response :unauthorized, log_on_failure('Should not get access without admin role')
  end

  test "should destroy schema_right" do
    schema_right_to_delete = SchemaRight.new(user_id: User.where(email: 'no_schema_right@xy.com').first.id,
                                             schema_id: user_schema.id
    )
    run_with_current_user { schema_right_to_delete.save! }

    assert_difference('SchemaRight.count', -1) do
      delete schema_right_url(schema_right_to_delete), headers: jwt_header(@jwt_admin_token), params: { schema_right: schema_right_to_delete.attributes}, as: :json
    end
    assert_response 204

    if MovexCdc::Application.config.db_type != 'SQLITE'
      delete schema_right_url(SchemaRight.where(user_id: peter_user.id, schema_id: user_schema.id).first), headers: jwt_header(@jwt_admin_token), params: { schema_right: {lock_version: 42}}, as: :json
      assert_response :internal_server_error
      assert response.body['ActiveRecord::StaleObjectError'], log_on_failure('Should raise ActiveRecord::StaleObjectError')
    end

    delete schema_right_url(@schema_right), headers: jwt_header, as: :json
    assert_response :unauthorized, log_on_failure('Should not get access without admin role')
  end
end
