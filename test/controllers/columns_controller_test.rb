require 'test_helper'

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @column = columns(:one)
  end

  test "should get index" do
    get columns_url, headers: jwt_header, as: :json
    assert_response :success
  end

  test "should create column" do
    assert_difference('Column.count') do
      post columns_url, headers: jwt_header, params: { column: {  table_id: 1, name: 'New column', info: 'New info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y'  } }, as: :json
    end

    assert_response 201
  end

  test "should show column" do
    get column_url(@column), headers: jwt_header, as: :json
    assert_response :success
  end

  test "should update column" do
    patch column_url(@column), headers: jwt_header, params: { column: {  } }, as: :json
    assert_response 200
  end

  test "should destroy column" do
    assert_difference('Column.count', -1) do
      delete column_url(@column), headers: jwt_header, as: :json
    end

    assert_response 204
  end
end
