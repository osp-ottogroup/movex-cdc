require 'test_helper'

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @column = columns(:one)
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/columns?table_id=1", headers: jwt_header, as: :json
    assert_response :success

    assert_raise 'Should not get access without schema rights' do
      get "/columns?table_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end

  test "should create column" do
    assert_difference('Column.count') do
      post columns_url, headers: jwt_header, params: { column: {  table_id: 1, name: 'New column', info: 'New info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y'  } }, as: :json
    end
    assert_response 201

    assert_raise 'Should not get access without schema rights' do
      post columns_url, headers: jwt_header(@jwt_no_schema_right_token), params: { column: {  table_id: 1, name: 'New column', info: 'New info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y'  } }, as: :json
    end
  end

  test "should show column" do
    get column_url(@column), headers: jwt_header, as: :json
    assert_response :success

    assert_raise 'Should not get access without schema rights' do
      get column_url(@column), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end

  test "should update column" do
    patch column_url(@column), headers: jwt_header, params: { column: { yn_lock_delete: 'Y', lock_version: @column.lock_version } }, as: :json
    assert_response 200

    assert_raise 'Should not get access without schema rights' do
      patch column_url(@column), headers: jwt_header(@jwt_no_schema_right_token), params: { column: {  } }, as: :json
    end
  end

  test "should destroy column" do
    assert_difference('Column.count', -1) do
      delete column_url(@column), headers: jwt_header, as: :json
    end
    assert_response 204
  end

  test "should not destroy column" do
    assert_raise 'Should not get access without schema rights' do
      delete column_url(@column), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end

end
