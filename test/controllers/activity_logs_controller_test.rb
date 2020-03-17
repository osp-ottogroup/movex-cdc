require 'test_helper'

class ActivityLogsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do

    get "/activity_logs?user_id=1", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs?schema_name=SCHEMA", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs?schema_name=SCHEMA&table_name=TABLE", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs?schema_name=SCHEMA&table_name=TABLE&column_name=COLUMN", headers: jwt_header, as: :json
    assert_response :success

    assert_raise(Exception, 'At least one parameter') do
      get "/activity_logs", headers: jwt_header, as: :json
    end

  end

end
