require 'test_helper'

class ConditionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @condition = conditions(:one)
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/conditions?table_id=1", headers: jwt_header, as: :json
    assert_response :success

    get "/conditions?table_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "should create condition" do
    assert_difference('Condition.count') do
      post conditions_url, headers: jwt_header, params: { condition: { table_id: 1, operation: 'U', filter: 'ID IS NULL' } }, as: :json
    end
    assert_response 201

    post conditions_url, headers: jwt_header(@jwt_no_schema_right_token), params: { condition: {  table_id: 1, operation: 'U', filter: 'ID IS NULL'  } }, as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "should show condition" do
    get condition_url(@condition), headers: jwt_header, as: :json
    assert_response :success

    get condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "should update condition" do
    patch condition_url(@condition), headers: jwt_header, params: { condition: { filter: 'new filter', lock_version: @condition.lock_version } }, as: :json
    assert_response 200

    patch condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), params: { condition: {  } }, as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "should destroy condition" do
    assert_difference('Condition.count', -1) do
      delete condition_url(@condition), headers: jwt_header, params: { condition: @condition.attributes}, as: :json
    end
    assert_response 204

    assert_raise ActiveRecord::StaleObjectError, 'Should raise ActiveRecord::StaleObjectError' do
      delete condition_url(conditions(:two)), headers: jwt_header, params: { condition: {lock_version: 42}}, as: :json
    end

  end

  test "should not destroy condition" do
    delete condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), params: { condition: @condition.attributes}, as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

end
