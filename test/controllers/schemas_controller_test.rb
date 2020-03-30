require 'test_helper'

class SchemasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @schema = schemas(:one)
  end

  test "should get index for allowed schemata" do
    get schemas_url, headers: jwt_header, as: :json
    assert_response :success
    result = response.parsed_body

    case Trixx::Application.config.trixx_db_type
    when 'SQLITE' then
      assert_equal(1, result.count, 'Should return schema main only')
    else
      assert_equal(3, result.count, 'Should return the allowed schemas for user')
    end
  end

  test "should create schema" do
    assert_difference('Schema.count') do
      post schemas_url, headers: jwt_header, params: { schema: { name: 'Schema new'  } }, as: :json
    end
    assert_response 201

    assert_difference('Schema.count') do
      post schemas_url, headers: jwt_header, params: { schema: { name: 'Schema new2', topic: 'with_topic'  } }, as: :json
    end
    assert_response 201
  end

  test "should show schema" do
    get schema_url(@schema), headers: jwt_header, as: :json
    assert_response :success
  end

  test "should update schema" do
    patch schema_url(@schema), headers: jwt_header, params: { schema: { name: 'new_name', topic: 'new topic'} }, as: :json
    assert_response 200
  end

  test "should destroy schema" do
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      @deletable = Schema.new(name: 'Deletable')
      @deletable.save!
      assert_difference('Schema.count', -1) do
        delete schema_url(@deletable), headers: jwt_header, as: :json
      end
      assert_response 204
    when 'SQLITE' then                                                          # onle one schema exists for SQLite that should not be deleted
    end
  end

end
