require 'test_helper'

class DbSchemasControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get db_schemas_url, headers: jwt_header, as: :json
    assert_response :success
  end

  test "should get authorizable_schemas" do
    get '/db_schemas/authorizable_schemas?email=Gibt_es_nicht', headers: jwt_header, as: :json
    assert_response :success

    # Test with existing email
    get '/db_schemas/authorizable_schemas?email=Peter.Ramm@ottogroup.com', headers: jwt_header, as: :json
    assert_response :success
  end

  test "validate_user_name" do
    get "/db_schemas/validate_user_name?user_name=#{Trixx::Application.config.db_user}", headers: jwt_header, as: :json
    assert_response :success

    get "/db_schemas/validate_user_name?user_name=quatsch", headers: jwt_header, as: :json
    assert_response :not_found
  end
end
