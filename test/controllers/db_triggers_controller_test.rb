require 'test_helper'

class DbTriggersControllerTest < ActionDispatch::IntegrationTest

  setup do
    # TODO: create one trigger for tests
  end

  test 'should get index' do
    # Setting params for get leads to switch GET to POST, only in test
    get '/db_triggers?schema_id=1', headers: jwt_header, as: :json
    assert_response :success

    get "/db_triggers?schema_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

    get "/db_triggers?schema_id=177", headers: jwt_header, as: :json
    assert_response :unauthorized, 'Should get error for non existing schema'
  end

  test "show trigger" do
    get "/db_triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header, as: :json
    assert_response :success

    get "/db_triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

    assert_raise(Exception, 'Non existing table should raise exception') do
      get "/db_triggers/details?table_id=177&trigger_name=hugo", headers: jwt_header, as: :json
    end
  end

  test "generate triggers" do
    create_victim_structures

    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header, as: :json
    assert_response :success

    assert_raise(Exception, 'Unknown schema should raise exception') do
      post "/db_triggers/generate?schema_name=hugo", headers: jwt_header, as: :json
    end

    post "/db_triggers/generate?schema_name=#{Schema.find(victim_schema_id).name}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

    drop_victim_structures
  end

  test "generate all triggers" do
    create_victim_structures

    post "/db_triggers/generate_all", headers: jwt_header, as: :json
    assert_response :success

    post "/db_triggers/generate_all", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

    drop_victim_structures
  end


end
