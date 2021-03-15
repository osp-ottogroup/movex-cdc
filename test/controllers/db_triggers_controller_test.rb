require 'test_helper'

class DbTriggersControllerTest < ActionDispatch::IntegrationTest

  setup do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)
  end

  teardown do
    # Remove victim structures
    drop_victim_structures(@victim_connection, suppress_exception: true )
    logoff_victim_connection(@victim_connection)
  end

  test 'should get index' do
    # Setting params for get leads to switch GET to POST, only in test
    get '/db_triggers?schema_id=1', headers: jwt_header, as: :json
    assert_response :success

    get "/db_triggers?schema_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'

    get "/db_triggers?schema_id=177", headers: jwt_header, as: :json
    assert_response :internal_server_error, 'Should get error for non existing schema'
  end

  test "show trigger" do
    get "/db_triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header, as: :json
    assert_response :success

    get "/db_triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'

    assert_raise(Exception, 'Non existing table should raise exception') do
      get "/db_triggers/details?table_id=177&trigger_name=hugo", headers: jwt_header, as: :json
    end
  end

  test "generate triggers with failures" do
    post "/db_triggers/generate?schema_name=hugo", headers: jwt_header, as: :json
    assert_response :internal_server_error, 'Unknown schema should raise exception'

    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  def run_generate_triggers(params: {}, trigger_count_changed_expected:)
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema_id).count
    post "/db_triggers/generate", params: {schema_name: Schema.find(victim_schema_id).name}.merge(params), headers: jwt_header, as: :json
    assert_response :success
    if trigger_count_changed_expected
      assert_not_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, "trigger count should not be changed for #{params}")
    else
      assert_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, "trigger count should not be changed for #{params}")
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
    run_generate_triggers(params: { table_id_list: [tables(:victim1).id] }, trigger_count_changed_expected: true)
  end

  test "generate triggers table_id_list dry_run" do
    run_generate_triggers(params: { dry_run: true, table_id_list: [tables(:victim1).id] }, trigger_count_changed_expected: false)
  end

  test "generate all triggers with failures" do
    post "/db_triggers/generate_all", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :not_found, 'Should not get access without schema rights'
  end

  def run_generate_all_triggers(params: {}, trigger_count_changed_expected:)
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema_id).count
    post "/db_triggers/generate_all", params: params, headers: jwt_header, as: :json
    assert_response :success
    if trigger_count_changed_expected
      assert_not_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, "trigger count should not be changed for #{params}")
    else
      assert_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, "trigger count should not be changed for #{params}")
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
    run_generate_all_triggers(params: { table_id_list: [tables(:victim1).id] }, trigger_count_changed_expected: true)
  end

  test "generate all triggers table_id_list dry_run" do
    run_generate_all_triggers(params: { dry_run: true, table_id_list: [tables(:victim1).id] }, trigger_count_changed_expected: false)
  end

end
