require 'test_helper'

class DbTriggersControllerTest < ActionDispatch::IntegrationTest

  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test 'should get index' do
    # Setting params for get leads to switch GET to POST, only in test
    get "/db_triggers?schema_id=#{user_schema.id}", headers: jwt_header, as: :json
    assert_response :success

    get "/db_triggers?schema_id=#{user_schema.id}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')

    get "/db_triggers?schema_id=177", headers: jwt_header, as: :json
    assert_response :internal_server_error, log_on_failure('Should get error for non existing schema')
  end

  test "show trigger" do
    get "/db_triggers/details?table_id=#{tables_table.id}&trigger_name=hugo", headers: jwt_header, as: :json
    assert_response :success

    get "/db_triggers/details?table_id=#{tables_table.id}&trigger_name=hugo", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')

    get "/db_triggers/details?table_id=177&trigger_name=hugo", headers: jwt_header, as: :json
    assert_response :internal_server_error
    assert response.body['ActiveRecord::RecordNotFound'], log_on_failure('Should raise ActiveRecord::RecordNotFound')
  end

  test "generate triggers with failures" do
    post "/db_triggers/generate?schema_name=hugo", headers: jwt_header, as: :json
    assert_response :internal_server_error, log_on_failure('Unknown schema should raise exception')

    post "/db_triggers/generate?schema_name=#{victim_schema.name}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, log_on_failure('Should not get access without schema rights')

    condition = nil                                                             # define the variable for greater scope
    original_filter = nil                                                       # define the variable for greater scope
    run_with_current_user do
      condition = Condition.where(table_id: victim1_table.id, operation: 'I').first
      original_filter = condition.filter
      condition.update!(filter: "NOT EXECUTABLE SQL")                           # Set a condition that causes compile error for trigger
    end
    post "/db_triggers/generate?schema_name=#{victim_schema.name}", headers: jwt_header, as: :json
    assert_response 207, log_on_failure('Should return Multi-Status (207) even if trigger generation fails. The errors array has to be checked by the caller.')
    run_with_current_user do
      condition.update!(filter: original_filter)                                  # reset valid entry
    end
  end

  def run_generate_triggers(params: {}, trigger_count_changed_expected:)
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema.id).count
    post "/db_triggers/generate", params: {schema_name: victim_schema.name}.merge(params), headers: jwt_header, as: :json
    assert_response :success
    if trigger_count_changed_expected
      assert_not_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema.id).count, log_on_failure("trigger count should not be changed for #{params}"))
    else
      assert_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema.id).count, log_on_failure("trigger count should not be changed for #{params}"))
    end
  end

  test "generate triggers" do
    run_generate_triggers(trigger_count_changed_expected: true)
  end

  test "generate triggers dry_run" do
    run_generate_triggers(params: { dry_run: true}, trigger_count_changed_expected: false)
  end

  test "generate triggers table_id_list not in" do
    run_generate_triggers(params: { table_id_list: [1278, 5664] }, trigger_count_changed_expected: false)
  end

  test "generate triggers table_id_list in" do
    run_generate_triggers(params: { table_id_list: [victim1_table.id] }, trigger_count_changed_expected: true)
  end

  test "generate triggers table_id_list dry_run" do
    run_generate_triggers(params: { dry_run: true, table_id_list: [victim1_table.id] }, trigger_count_changed_expected: false)
  end

  test "generate all triggers with failures" do
    post "/db_triggers/generate_all", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :not_found, log_on_failure('Should not get access without schema rights')

    condition = nil                                                             # define the variable for greater scope
    original_filter = nil                                                       # define the variable for greater scope
    run_with_current_user do
      condition = Condition.where(table_id: victim1_table.id, operation: 'I').first
      original_filter = condition.filter
      condition.update!(filter: "NOT EXECUTABLE SQL")                           # Set a condition that causes compile error for trigger
    end
    post "/db_triggers/generate_all", headers: jwt_header, as: :json
    assert_response 207, log_on_failure('Should return Multi-Status (207) even if trigger generation fails. The errors array has to be checked by the caller.')
    run_with_current_user do
      condition.update!(filter: original_filter)                                  # reset valid entry
    end
  end

  def run_generate_all_triggers(params: {}, trigger_count_changed_expected:)
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema.id).count
    post "/db_triggers/generate_all", params: params, headers: jwt_header, as: :json
    assert_response :ok
    if trigger_count_changed_expected
      assert_not_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema.id).count, log_on_failure("trigger count should not be changed for #{params}"))
    else
      assert_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema.id).count, log_on_failure("trigger count should not be changed for #{params}"))
    end
  end

  test "generate all triggers" do
    run_generate_all_triggers(trigger_count_changed_expected: true)
  end

  test "generate all triggers dry_run" do
    run_generate_all_triggers(params: { dry_run: true }, trigger_count_changed_expected: false)
  end

  test "generate all triggers table_id_list not in" do
    run_generate_all_triggers(params: { table_id_list: [1278, 5664] }, trigger_count_changed_expected: false)
  end

  test "generate all triggers table_id_list in" do
    run_generate_all_triggers(params: { table_id_list: [victim1_table.id] }, trigger_count_changed_expected: true)
  end

  test "generate all triggers table_id_list dry_run" do
    run_generate_all_triggers(params: { dry_run: true, table_id_list: [victim1_table.id] }, trigger_count_changed_expected: false)
  end
end
