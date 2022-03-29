require 'test_helper'

class ConditionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @condition = Condition.where(table_id: victim1_table.id, operation: 'I').first
    create_victim_structures
  end

  test "should get index" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/conditions?table_id=#{victim1_table.id}", headers: jwt_header, as: :json
    assert_response :success

    get "/conditions?table_id=#{tables_table.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should create condition" do
    assert_difference('Condition.count') do
      post conditions_url, headers: jwt_header, params: { condition: { table_id: victim1_table.id, operation: 'U', filter: 'ID IS NULL' } }, as: :json
    end
    assert_response 201

    run_with_current_user { Condition.where(filter: 'ID IS NULL').first.destroy! } # restore previous state

    post conditions_url, headers: jwt_header(@jwt_no_schema_right_token), params: { condition: {  table_id: tables_table.id, operation: 'U', filter: 'ID IS NULL'  } }, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should show condition" do
    get condition_url(@condition), headers: jwt_header, as: :json
    assert_response :success

    get condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should update condition" do
    org_filter = @condition.filter
    patch condition_url(@condition), headers: jwt_header, params: { condition: { filter: 'new filter', lock_version: @condition.lock_version } }, as: :json
    assert_response 200

    condition = Condition.find(@condition.id)                                   # load fresh state from DB
    run_with_current_user { condition.update!(filter: org_filter, lock_version: condition.lock_version) } # Restore previous state

    patch condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), params: { condition: {  } }, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

  test "should destroy condition" do
    condition_to_delete = Condition.new(table_id: victim2_table.id, operation: 'D', filter: '1=1')
    run_with_current_user { condition_to_delete.save! }

    assert_difference('Condition.count', -1) do
      delete condition_url(condition_to_delete), headers: jwt_header, params: { condition: condition_to_delete.attributes}, as: :json
    end
    assert_response 204

    condition = Condition.where(table_id: victim1_table.id, operation: 'D').first
    delete condition_url(condition), headers: jwt_header, params: { condition: {lock_version: 42}}, as: :json
    assert_response :internal_server_error
    assert response.body['ActiveRecord::StaleObjectError'], log_on_failure('Should raise ActiveRecord::StaleObjectError')
  end

  test "should not destroy condition" do
    delete condition_url(@condition), headers: jwt_header(@jwt_no_schema_right_token), params: { condition: @condition.attributes}, as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')
  end

end
