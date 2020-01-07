require 'test_helper'

class SchemasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @schema = schemas(:one)
  end

  test "should get index" do
    get schemas_url, headers: jwt_header, as: :json
    assert_response :success
  end

  test "should create schema" do
    assert_difference('Schema.count') do
      post schemas_url, headers: jwt_header, params: { schema: { name: 'Schema new'  } }, as: :json
    end

    assert_response 201
  end

  test "should show schema" do
    get schema_url(@schema), headers: jwt_header, as: :json
    assert_response :success
  end

  test "should update schema" do
    patch schema_url(@schema), headers: jwt_header, params: { schema: {  } }, as: :json
    assert_response 200
  end

  test "should destroy schema" do
    assert_difference('Schema.count', -1) do
      delete schema_url(@schema), headers: jwt_header, as: :json
    end

    assert_response 204
  end
end
