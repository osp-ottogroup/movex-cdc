require 'test_helper'

class ImportExportControllerTest < ActionDispatch::IntegrationTest

  # Test Goal: Ensure that the export of all schemas generates the correct json
  test "export all" do
    get "/import_export", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    Rails.logger.debug('ImportExportControllerTest.export'){ @response.body }
    actual = JSON.parse(@response.body)                                         # Ensure result is valid JSON

    assert(actual['schemas'].count == Schema.all.count, "All schemas should be exported")
    assert(actual['users'].count == User.all.count, "All users should be exported")

    get "/import_export", headers: jwt_header(@jwt_token)
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  # Test Goal: Ensure that the export of a single schema generates the correct json
  test "export schema" do
    db_user = MovexCdc::Application.config.db_user

    get "/import_export/#{db_user}", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    Rails.logger.debug('ImportExportControllerTest.export_schema'){ @response.body }
    actual = JSON.parse(@response.body)

    assert(actual['schemas'].count == 1, "Exactly one schema should be exported")
    assert(actual['users'].count == User.all.count, "All users should be exported")

    get "/import_export/#{db_user}", headers: jwt_header(@jwt_token)
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  test "import_all" do
    users   = ImportExportConfig.new.export_users
    schemas = ImportExportConfig.new.export_schemas(Schema.all)

    post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: users, schemas: schemas}
    assert_response :success

    post "/import_export", headers: jwt_header(@jwt_token), params: {users: users, schemas: schemas}
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  test "import schema" do
    # TODO: establish import API for single schema out of whole JSON with multiple schemas
  end
end
