require 'test_helper'

class ColumnExpressionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @column_expression = ColumnExpression.where(table_id: victim1_table.id, operation: 'I').first
    create_victim_structures
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/column_expressions?table_id=#{victim1_table.id}", headers: jwt_header, as: :json
    assert_response :success

    get "/column_expressions?table_id=#{tables_table.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should create column_expression" do
    sql = "SELECT Name Hugo FROM #{victim1_table.name} WHERE ID = :new.ID"
    assert_difference('ColumnExpression.count') do
      post "/column_expressions", headers: jwt_header, params: { column_expression: { table_id: victim1_table.id, operation: 'U', sql: sql } }, as: :json
    end
    assert_response 201

    run_with_current_user { ColumnExpression.where(sql: sql).first.destroy! } # restore previous state

    post "/column_expressions", headers: jwt_header(@jwt_no_schema_right_token), params: { column_expression: {  table_id: tables_table.id, operation: 'U', sql: sql  } }, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should show column_expression" do
    get "/column_expressions/#{@column_expression.id}", headers: jwt_header, as: :json
    assert_response :success

    get "/column_expressions/#{@column_expression.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should update column_expression" do
    org_sql = @column_expression.sql
    patch "/column_expressions/#{@column_expression.id}", headers: jwt_header, params: { column_expression: { sql: 'SELECT new', lock_version: @column_expression.lock_version } }, as: :json
    assert_response 200

    column_expression = ColumnExpression.find(@column_expression.id)                                   # load fresh state from DB
    run_with_current_user { column_expression.update!(sql: org_sql, lock_version: column_expression.lock_version) } # Restore previous state

    patch "/column_expressions/#{@column_expression.id}", headers: jwt_header(@jwt_no_schema_right_token), params: { column_expression: {  } }, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should destroy column_expression" do
    column_expression_to_delete = ColumnExpression.new(table_id: victim2_table.id, operation: 'D', sql: 'SELECT')
    run_with_current_user { column_expression_to_delete.save! }

    assert_difference('ColumnExpression.count', -1) do
      delete"/column_expressions/#{column_expression_to_delete.id}", headers: jwt_header, params: { column_expression: column_expression_to_delete.attributes}, as: :json
    end
    assert_response 204

    column_expression = ColumnExpression.where(table_id: victim1_table.id, operation: 'D').first
    delete"/column_expressions/#{@column_expression.id}", headers: jwt_header, params: { column_expression: {lock_version: 42}}, as: :json
    assert_response :internal_server_error
    assert response.body['ActiveRecord::StaleObjectError'], log_on_failure('Should raise ActiveRecord::StaleObjectError')
  end

  test "should not destroy column_expression" do
    delete "/column_expressions/#{@column_expression.id}", headers: jwt_header(@jwt_no_schema_right_token), params: { column_expression: @column_expression.attributes}, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

end
