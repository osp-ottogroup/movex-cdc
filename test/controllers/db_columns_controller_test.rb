require 'test_helper'

class DbColumnsControllerTest < ActionDispatch::IntegrationTest


  test "should get index with parameters" do
    # Setting params for get leads to switch GET to POST, only in test
    get "/db_columns?schema_name=#{Trixx::Application.config.trixx_db_user}&table_name=TABLES", headers: jwt_header, as: :json
    #    get db_tables_url, headers: jwt_header, as: :json, params: { schema_name: Trixx::Application.config.trixx_db_user}
    assert_response :success
  end

  test "should raise error without parameters" do
    assert_raise(ActionController::ParameterMissing, 'Should raise exception due to missing parameter') do
      get db_columns_url, headers: jwt_header, as: :json
    end
  end

end
