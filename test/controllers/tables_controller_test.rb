require 'test_helper'

class TablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @table = tables(:one)
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/tables?schema_id=1", headers: jwt_header, as: :json
    assert_response :success

    assert_raise 'Should not get access without schema rights' do
      get "/tables?schema_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end

  test "should create table" do
    assert_difference('Table.count') do
      post tables_url, headers: jwt_header, params: { table: { schema_id: 1, name: 'New table', info: 'New info' } }, as: :json
    end
    assert_response 201

    assert_difference('Table.count') do
      post tables_url, headers: jwt_header, params: { table: { schema_id: 1, name: 'New table2', info: 'New info', topic: 'with_topic' } }, as: :json
    end
    assert_response 201

    assert_raise 'Should not get access without schema rights' do
      post tables_url, headers: jwt_header(@jwt_no_schema_right_token), params: { table: { schema_id: 1, name: 'New table', info: 'New info' } }, as: :json
    end
  end

  test "should show table" do
    get table_url(@table), headers: jwt_header, as: :json
    assert_response :success

    assert_raise 'Should not get access without schema rights' do
      get table_url(@table), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end

  test "should get trigger dates of table" do
    get "/trigger_dates/#{@table.id}", headers: jwt_header, as: :json
    assert_response :success

    assert_raise 'Should not get access without schema rights' do
      get "/trigger_dates/#{@table.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end


  test "should update table" do
    patch table_url(@table), headers: jwt_header, params: { table: { schema_id: 1, name: 'new name', topic: 'new topic' } }, as: :json
    assert_response 200

    assert_raise 'Should not get access without schema rights' do
      patch table_url(@table), headers: jwt_header(@jwt_no_schema_right_token), params: { table: { schema_id: 1,  } }, as: :json
    end
  end

  test "should destroy table" do
    assert_difference('Table.count', -1) do
      delete table_url(tables(:deletable)), headers: jwt_header, as: :json
    end
    assert_response 204
  end

  test "should not destroy table" do
    assert_raise 'Should not get access without schema rights' do
      delete table_url(tables(:deletable)), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end
end
