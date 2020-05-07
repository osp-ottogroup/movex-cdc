require 'test_helper'

class DbTriggersControllerTest < ActionDispatch::IntegrationTest

  setup do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)
  end

  teardown do
    # Remove victim structures
    drop_victim_structures(@victim_connection)
    logoff_victim_connection(@victim_connection)
  end

  test 'should get index' do
    # Setting params for get leads to switch GET to POST, only in test
    get '/db_triggers?schema_id=1', headers: jwt_header, as: :json
    assert_response :success

    assert_raise 'Should not get access without schema rights' do
      get "/db_triggers?schema_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end

    assert_raise(Exception, 'Should get error for non existing schema') do
      get "/db_triggers?schema_id=177", headers: jwt_header, as: :json
    end
  end

  test "show trigger" do
    get "/db_triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header, as: :json
    assert_response :success

    assert_raise(Exception, 'Should not get access without schema rights') do
      get "/db_triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end

    assert_raise(Exception, 'Non existing table should raise exception') do
      get "/db_triggers/details?table_id=177&trigger_name=hugo", headers: jwt_header, as: :json
    end
  end

  test "generate triggers" do
    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header, as: :json
    assert_response :success

    assert_raise(Exception, 'Unknown schema should raise exception') do
      post "/db_triggers/generate?schema_name=hugo", headers: jwt_header, as: :json
    end

    assert_raise(Exception, 'Should not get access without schema rights') do
      post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    end
  end

  test "generate all triggers" do
    post "/db_triggers/generate_all", headers: jwt_header, as: :json
    assert_response :success

    post "/db_triggers/generate_all", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :not_found, 'Should not get access without schema rights'
  end


end
