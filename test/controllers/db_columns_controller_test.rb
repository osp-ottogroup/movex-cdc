require 'test_helper'

class DbColumnsControllerTest < ActionDispatch::IntegrationTest


  test "should get index with parameters" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/db_columns?schema_name=#{MovexCdc::Application.config.db_user}&table_name=TABLES", headers: jwt_header, as: :json
    #    get db_tables_url, headers: jwt_header, as: :json, params: { schema_name: MovexCdc::Application.config.db_user}
    assert_response :success
  end

  test "should raise error without parameters" do
    get "/db_columns", headers: jwt_header, as: :json
    assert_response :internal_server_error
    assert response.body['ActionController::ParameterMissing'], log_on_failure('Should raise ActionController::ParameterMissing')
  end

end
