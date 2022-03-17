require 'test_helper'

class ImportExportControllerTest < ActionDispatch::IntegrationTest

  # Test Goal: Ensure that the export of all schemas generates the correct json
  test "export all schemas" do
    get "/import_export/export", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    Rails.logger.debug('ImportExportControllerTest.export'){ @response.body }
    actual = JSON.parse(@response.body)                                         # Ensure result is valid JSON

    assert(actual['schemas'].count == Schema.all.count, "All schemas should be exported")
    assert(actual['users'].count == User.all.count, "All users should be exported")

    get "/import_export/export", headers: jwt_header(@jwt_token)
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  # Test Goal: Ensure that the export of a single schema generates the correct json
  test "export single schema" do
    db_user = MovexCdc::Application.config.db_user

    get "/import_export/export", headers: jwt_header(@jwt_admin_token), params: { schema: db_user}
    assert_response :success

    Rails.logger.debug('ImportExportControllerTest.export_schema'){ @response.body }
    actual = JSON.parse(@response.body)

    assert(actual['schemas'].count == 1, "Exactly one schema should be exported")
    assert(actual['users'].count == User.all.count, "All users should be exported")

    get "/import_export/export", headers: jwt_header(@jwt_token), params: { schema: db_user}
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  test "import all schemas" do
    json_data = ImportExportConfig.new.export

    # import as structured parameters / JSON and as String e.g. used by curl without application/content
    [json_data, JSON.pretty_generate(json_data)].each do |import_data|
      post "/import_export/import", headers: jwt_header(@jwt_admin_token), params: {json_data: import_data}
      assert_response :success
    end

    post "/import_export/import", headers: jwt_header(@jwt_token), params: {json_data: json_data}
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  test "import single schema" do
    db_user = MovexCdc::Application.config.db_user
    json_data = ImportExportConfig.new.export

    # import as structured parameters / JSON and as String e.g. used by curl without application/content
    [json_data, JSON.pretty_generate(json_data)].each do |import_data|
      post "/import_export/import", headers: jwt_header(@jwt_admin_token), params: {json_data: import_data, schema: db_user}
      assert_response :success
    end

    post "/import_export/import", headers: jwt_header(@jwt_token), params: {json_data: json_data, schema: db_user}
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end

  test 'import all users' do
    json_data = ImportExportConfig.new.export

    # import as structured parameters / JSON and as String e.g. used by curl without application/content
    [json_data, JSON.pretty_generate(json_data)].each do |import_data|
      post "/import_export/import_all_users", headers: jwt_header(@jwt_admin_token), params: {json_data: import_data}
      assert_response :success
    end

    post "/import_export/import_all_users", headers: jwt_header(@jwt_token), params: {json_data: json_data}
    assert_response :unauthorized, log_on_failure('Access allowed to supervisor only')
  end
end
