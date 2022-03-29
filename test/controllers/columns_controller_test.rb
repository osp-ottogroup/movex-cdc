require 'test_helper'

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @column = Column.where(name: 'CHAR_NAME').first
    create_victim_structures
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/columns?table_id=#{victim1_table.id}", headers: jwt_header, as: :json
    assert_response :success

    get "/columns?table_id=#{victim1_table.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should create column" do
    assert_difference('Column.count') do
      post columns_url, headers: jwt_header, params: { column: {  table_id: victim1_table.id, name: 'New column', info: 'New info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y'  } }, as: :json
    end
    assert_response 201

    post columns_url, headers: jwt_header(@jwt_no_schema_right_token), params: { column: {  table_id: tables_table.id, name: 'New column', info: 'New info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y'  } }, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')

    run_with_current_user { Column.where(name: 'New column').first.destroy! }                            # Restore original state
  end

  test "should show column" do
    get column_url(@column), headers: jwt_header, as: :json
    assert_response :success

    get column_url(@column), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should update column" do
    patch column_url(@column), headers: jwt_header, params: { column: { yn_lock_delete: 'Y', lock_version: @column.lock_version } }, as: :json
    assert_response 200

    patch column_url(@column), headers: jwt_header(@jwt_no_schema_right_token), params: { column: {  } }, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should destroy column" do
    column_to_destroy = Column.new(table_id: victim1_table.id, name: 'Dummy43', yn_log_insert: 'N', yn_log_update: 'N', yn_log_delete: 'N')
    run_with_current_user { column_to_destroy.save! }
    assert_difference('Column.count', -1) do
      delete column_url(column_to_destroy), headers: jwt_header, params: { column: column_to_destroy.attributes}, as: :json
    end
    assert_response 204


    column_to_destroy = Column.new(table_id: victim1_table.id, name: 'Dummy43', yn_log_insert: 'N', yn_log_update: 'N', yn_log_delete: 'N')
    run_with_current_user { column_to_destroy.save! }
    delete column_url(column_to_destroy), headers: jwt_header, params: { column: {lock_version: 42}}, as: :json
    assert_response :internal_server_error
    assert response.body['ActiveRecord::StaleObjectError'], log_on_failure('Should raise ActiveRecord::StaleObjectError')
    run_with_current_user { column_to_destroy.destroy! }
  end

  test "should not destroy column" do
    delete column_url(@column), headers: jwt_header(@jwt_no_schema_right_token), params: { column: @column.attributes}, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should tag operation for all columns" do
    ['I', 'U', 'D'].each do |operation|
      post "/columns/deselect_all_columns", headers: jwt_header, params: { table_id: @column.table_id, operation: operation}, as: :json
      assert_response :success

      post "/columns/select_all_columns", headers: jwt_header, params: { table_id: @column.table_id, operation: operation}, as: :json
      assert_response :success

      # Ensure all colums are left selected after test
    end
  end

end
