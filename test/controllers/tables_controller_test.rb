require 'test_helper'

class TablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @table              = tables(:one)
    @victim1_table      = tables(:victim1)
    @victim_connection  = create_victim_connection
    create_victim_structures(@victim_connection)
    @victim_schema_id = Trixx::Application.config.trixx_db_victim_schema_id
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/tables?schema_id=1", headers: jwt_header, as: :json
    assert_response :success

    get "/tables?schema_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "should create table" do
    def remove_created_table(table_name)
      Database.execute "DELETE FROM Tables WHERE Schema_ID = :schema_id AND Name = :name", schema_id:victim_schema_id, name: table_name
    end

    assert_difference('Table.count') do
      post tables_url, headers: jwt_header, params: { table: { schema_id: @victim_schema_id, name: 'VICTIM3', info: 'New info' } }, as: :json
    end
    assert_response 201

    remove_created_table('VICTIM3')                                             # Remove Tables-record for next try with same name

    assert_difference('Table.count') do
      post tables_url, headers: jwt_header, params: { table: { schema_id: @victim_schema_id, name: 'VICTIM3', info: 'New info', topic: KafkaHelper.existing_topic_for_test } }, as: :json
    end
    assert_response 201

    post tables_url, headers: jwt_header(@jwt_no_schema_right_token), params: { table: { schema_id: @victim_schema_id, name: 'VICTIM3', info: 'New info' } }, as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'

    # reopen hidden table instead of creation
    tables_deletable = Table.find_by_schema_id_and_name(@victim_schema_id, 'VICTIM3')
    tables_deletable.update(yn_hidden: 'Y')
    assert_no_difference('Table.count') do
      post tables_url, headers: jwt_header, params: { table: { schema_id: tables_deletable.schema_id, name: tables_deletable.name, info: 'different info', topic: KafkaHelper.existing_topic_for_test } }, as: :json
    end
    assert_response :success, 'Table should be updated'
    result_table = Table.find(tables_deletable.id)
    assert_equal 'N', result_table.yn_hidden, 'Table should not be hidden after create'
    assert_equal 'different info', result_table.info, 'Hidden table should be updated with new values'
  end

  test "should show table" do
    get table_url(@victim1_table ), headers: jwt_header, as: :json
    assert_response :success

    get table_url(@table), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "should get trigger dates of table" do
    get "/trigger_dates/#{@table.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'

    get "/trigger_dates/#{@victim1_table.id}", headers: jwt_header, as: :json
    assert_response :success
  end


  test "should update table" do
    patch table_url(@victim1_table), headers: jwt_header, params: { table: { info: 'new info', topic: KafkaHelper.existing_topic_for_test, lock_version: @table.lock_version } }, as: :json
    assert_response 200

    patch table_url(@table), headers: jwt_header(@jwt_no_schema_right_token), params: { table: { schema_id: 1,  } }, as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'

    assert_raise ActiveRecord::StaleObjectError, 'Should raise ActiveRecord::StaleObjectError' do
      patch table_url(@victim1_table), headers: jwt_header, params: { table: { info: 'newer info', topic: KafkaHelper.existing_topic_for_test, lock_version: 42 } }, as: :json
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
    delete table_url(@deletable), headers: jwt_header(@jwt_no_schema_right_token), params: { table: @deletable.attributes}, as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end
end
