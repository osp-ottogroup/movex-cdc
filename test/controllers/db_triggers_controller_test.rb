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

  test "generate triggers" do
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema_id).count
    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header, as: :json
    assert_response :success
    assert_not_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, 'trigger count should be changed by dry run')

    post "/db_triggers/generate?schema_name=hugo", headers: jwt_header, as: :json
    assert_response :internal_server_error, 'Unknown schema should raise exception'

    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :internal_server_error, 'Should not get access without schema rights'
  end

  test "generate triggers dry_run" do
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema_id).count

    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}&dry_run=true", headers: jwt_header, as: :json
    assert_response :success

    assert_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, 'trigger count should not be changed by dry run')
  end


  test "generate all triggers" do
    post "/db_triggers/generate_all", headers: jwt_header, as: :json
    assert_response :success

    post "/db_triggers/generate_all", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :not_found, 'Should not get access without schema rights'
  end

  test "generate all triggers dry_run" do
    existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema_id).count

    post "/db_triggers/generate_all?dry_run=true", headers: jwt_header, as: :json
    assert_response :success

    assert_equal(existing_triggers_before, DbTrigger.find_all_by_schema_id(victim_schema_id).count, 'trigger count should not be changed by dry run')
  end

end
