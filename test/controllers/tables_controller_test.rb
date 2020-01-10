require 'test_helper'

class TablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @table = tables(:one)
  end

  test "should get index" do
    get tables_url, headers: jwt_header, as: :json
    assert_response :success
  end

  test "should create table" do
    assert_difference('Table.count') do
      post tables_url, headers: jwt_header, params: { table: { schema_id: 1, name: 'New table', info: 'New info' } }, as: :json
    end

    assert_response 201
  end

  test "should show table" do
    get table_url(@table), headers: jwt_header, as: :json
    assert_response :success
  end

  test "should update table" do
    patch table_url(@table), headers: jwt_header, params: { table: {  } }, as: :json
    assert_response 200
  end

  test "should destroy table" do
    assert_difference('Table.count', -1) do
      delete table_url(tables(:deletable)), headers: jwt_header, as: :json
    end

    assert_response 204
  end
end
