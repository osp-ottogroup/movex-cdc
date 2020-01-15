require 'test_helper'

class DbSchemasControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get db_schemas_url, headers: jwt_header, as: :json
    assert_response :success
  end

end
