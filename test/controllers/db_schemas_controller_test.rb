require 'test_helper'

class DbSchemasControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get db_schemas_url, headers: jwt_header, as: :json
    assert_response :success
  end

  test "should get remaining_schemas" do
    get '/db_schemas/remaining_schemas?email=Gibt_es_nicht', headers: jwt_header, as: :json
    assert_response :success

    # Test with existing email
    get '/db_schemas/remaining_schemas?email=Peter.Ramm@ottogroup.com', headers: jwt_header, as: :json
    assert_response :success
  end

end
