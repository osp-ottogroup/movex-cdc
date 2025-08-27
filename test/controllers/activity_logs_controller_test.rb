require 'test_helper'

class ActivityLogsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do

    get "/activity_logs?user_id=#{peter_user.id}", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs?schema_name=SCHEMA", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs?schema_name=SCHEMA&table_name=TABLE", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs?schema_name=SCHEMA&table_name=TABLE&column_name=COLUMN", headers: jwt_header, as: :json
    assert_response :success

    get "/activity_logs", headers: jwt_header, as: :json
    assert_response :internal_server_error, log_on_failure('At least one parameter')
  end

  test "should create activity_log" do
    ActivityLogsController::ALLOWED_LEVELS.each do |level|
      assert_difference('ActivityLog.count') do
        post "/activity_logs", headers: jwt_header, params: { activity_log: {  level: level, user_id: peter_user.id, schema_name: 'Schema1', table_name: 'Table1', column_name: 'Column1', action: 'Something happened' } }, as: :json
      end
      assert_response 201
    end

    post "/activity_logs", headers: jwt_header, params: { activity_log: {  level: 'hugo', user_id: peter_user.id, schema_name: 'Schema1', table_name: 'Table1', column_name: 'Column1', action: 'Something happened' } }, as: :json
    assert_response :internal_server_error
  end
end
