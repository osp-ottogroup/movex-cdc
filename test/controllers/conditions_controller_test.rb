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
    assert_response :unauthorized, 'Should not get access without schema rights'
  end

  test "should create condition" do
    assert_difference('Condition.count') do
      post conditions_url, headers: jwt_header, params: { condition: { table_id: 1, operation: 'U', filter: 'ID IS NULL' } }, as: :json
    end
    assert_response 201

    post conditions_url, headers: jwt_header(@jwt_no_schema_right_token), params: { condition: {  table_id: 1, operation: 'U', filter: 'ID IS NULL'  } }, as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'
  end

  test "should show condition" do
    get condition_url(@condition), headers: jwt_header, as: :json
    assert_response :success

    get condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'
  end

  test "should update condition" do
    patch condition_url(@condition), headers: jwt_header, params: { condition: {  } }, as: :json
    assert_response 200

    patch condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), params: { condition: {  } }, as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'
  end

  test "should destroy condition" do
    assert_difference('Condition.count', -1) do
      delete condition_url(@condition), headers: jwt_header, as: :json
    end
    assert_response 204
  end

  test "should not destroy condition" do
    delete condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'
  end

end
