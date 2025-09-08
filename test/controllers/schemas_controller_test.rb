require 'test_helper'

class SchemasControllerTest < ActionDispatch::IntegrationTest
  setup do
  end

  test "should get index for allowed schemata" do
    get "/schemas", headers: jwt_header, as: :json
    assert_response :success
    result = response.parsed_body

    case MovexCdc::Application.config.db_type
    when 'SQLITE' then
      assert_equal(1, result.count, log_on_failure('Should return schema main only'))
    else
      assert_equal(2, result.count, log_on_failure('Should return the allowed schemas for user'))
    end
  end

  test "should create schema" do
    assert_difference('Schema.count') do
      post "/schemas", headers: jwt_header, params: { schema: { name: 'Schema new'  } }, as: :json
    end
    assert_response 201

    assert_difference('Schema.count') do
      post "/schemas", headers: jwt_header, params: { schema: { name: 'Schema new2', topic: KafkaHelper.existing_topic_for_test  } }, as: :json
    end
    assert_response 201
  end

  test "should show schema" do
    get "/schemas/#{user_schema.id}", headers: jwt_header, as: :json
    assert_response :success
  end

  test "should update schema" do
    schema = Schema.find(user_schema.id)
    patch "/schemas/#{schema.id}", headers: jwt_header, params: { schema: { name: 'new_name', topic: KafkaHelper.existing_topic_for_test, lock_version: schema.lock_version} }, as: :json
    assert_response 200
    run_with_current_user { Schema.find(user_schema.id).update!(user_schema.attributes.select{|key, value| key != 'lock_version'}) } # Restore original state
  end

  test "should destroy schema" do
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      @deletable = Schema.new(name: 'Deletable', lock_version: 1)
      run_with_current_user { @deletable.save! }
      assert_difference('Schema.count', -1) do
        delete "/schemas/#{@deletable.id}", headers: jwt_header, params: { schema: @deletable.attributes}, as: :json
      end
      assert_response 204

      @deletable = Schema.new(name: 'Deletable', lock_version: 1)
      run_with_current_user { @deletable.save! }
      delete "/schemas/#{@deletable.id}", headers: jwt_header, params: { schema: {lock_version: 42}}, as: :json
      assert_response :internal_server_error
      assert response.body['ActiveRecord::StaleObjectError'], log_on_failure('Should raise ActiveRecord::StaleObjectError')
    when 'SQLITE' then                                                          # onle one schema exists for SQLite that should not be deleted
    end
  end

end
