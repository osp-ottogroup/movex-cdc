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
      post tables_url, headers: jwt_header, params: { table: { schema_id: 1, name: 'New table2', info: 'New info', topic: KafkaHelper.existing_topic_for_test } }, as: :json
    end
    assert_response 201

    assert_raise 'Should not get access without schema rights' do
      post tables_url, headers: jwt_header(@jwt_no_schema_right_token), params: { table: { schema_id: 1, name: 'New table', info: 'New info' } }, as: :json
    end

    # reopen hidden table instead of creation
    tables_deletable = tables(:deletable)
    tables_deletable.update(yn_hidden: 'Y')
    post tables_url, headers: jwt_header, params: { table: { schema_id: tables_deletable.schema_id, name: tables_deletable.name, info: 'different info', topic: KafkaHelper.existing_topic_for_test } }, as: :json
    assert_response :success, 'Table should be updated'
    result_table = Table.find(tables_deletable.id)
    assert_equal 'N', result_table.yn_hidden, 'Table should not be hidden after create'
    assert_equal 'different info', result_table.info, 'Hidden table should be updated with new values'
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
    patch table_url(@table), headers: jwt_header, params: { table: { schema_id: 1, name: 'new name', topic: KafkaHelper.existing_topic_for_test, lock_version: @table.lock_version } }, as: :json
    assert_response 200

    assert_raise 'Should not get access without schema rights' do
      patch table_url(@table), headers: jwt_header(@jwt_no_schema_right_token), params: { table: { schema_id: 1,  } }, as: :json
    end
  end

  test "should destroy table" do
    @deletable = tables(:deletable)
    assert_difference('Table.count', 0) do                                      # Table should be marked hidden
      delete table_url(@deletable), headers: jwt_header, params: { table: @deletable.attributes}, as: :json
    end
    assert_response 204
    assert_equal 'Y', Table.find(tables(:deletable).id).yn_hidden, 'Table should be hidden after destroy'

    assert_raise ActiveRecord::StaleObjectError, 'Should raise ActiveRecord::StaleObjectError' do
      delete table_url(@deletable), headers: jwt_header, params: { table: {lock_version: 42}}, as: :json
    end

  end

  test "should not destroy table" do
    @deletable = tables(:deletable)
    assert_raise 'Should not get access without schema rights' do
      delete table_url(@deletable), headers: jwt_header(@jwt_no_schema_right_token), params: { table: @deletable.attributes}, as: :json
    end
  end
end
