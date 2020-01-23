require 'test_helper'

class TriggersControllerTest < ActionDispatch::IntegrationTest

  setup do
    # TODO: create one trigger for tests
  end

  test 'should get index' do
    # Setting params for get leads to switch GET to POST, only in test
    get '/triggers?schema_id=1', headers: jwt_header, as: :json
    assert_response :success

    get "/triggers?schema_id=1", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

    get "/triggers?schema_id=177", headers: jwt_header, as: :json
    assert_response :unauthorized, 'Should get error for non existing schema'
  end

  test "show trigger" do
    get "/triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header, as: :json
    assert_response :success

    get "/triggers/details?table_id=1&trigger_name=hugo", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

    assert_raise(Exception, 'Non existing table should raise exception') do
      get "/triggers/details?table_id=177&trigger_name=hugo", headers: jwt_header, as: :json
    end
  end

  test "generate triggers" do
    post "/triggers/generate?schema_name=#{Trixx::Application.config.trixx_db_user}", headers: jwt_header, as: :json
    assert_response :success

    assert_raise(Exception, 'Unknown schema should raise exception') do
      post "/triggers/generate?schema_name=hugo", headers: jwt_header, as: :json
    end

    post "/triggers/generate?schema_name=#{Trixx::Application.config.trixx_db_user}", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'
  end

  test "generate all triggers" do
    post "/triggers/generate_all", headers: jwt_header, as: :json
    assert_response :success

    post "/triggers/generate_all", headers: jwt_header(@jwt_no_schema_right_token), as: :json
    assert_response :unauthorized, 'Should not get access without schema rights'

  end


end
