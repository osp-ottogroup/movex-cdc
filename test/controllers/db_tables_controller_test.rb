require 'test_helper'

class DbTablesControllerTest < ActionDispatch::IntegrationTest

  test "should get index with parameters" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/db_tables?schema_name=#{MovexCdc::Application.config.db_user}", headers: jwt_header, as: :json
    #    get "/db_tables", headers: jwt_header, as: :json, params: { schema_name: MovexCdc::Application.config.db_user}
    assert_response :success
  end

  test "should raise error without parameters" do
      get "/db_tables", headers: jwt_header, as: :json
      assert_response :internal_server_error
      assert response.body['ActionController::ParameterMissing'], log_on_failure('ActionController::ParameterMissing should be raised')
  end

=begin
  test "should get remaining with parameters" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/db_tables/remaining?schema_id=user_schema.id}", headers: jwt_header, as: :json
    #    get "/db_tables", headers: jwt_header, as: :json, params: { schema_name: MovexCdc::Application.config.db_user}
    assert_response :success
  end
=end

end
