require 'test_helper'

class TableControllerTest < ActionDispatch::IntegrationTest
  test "should get tables" do
    get table_tables_url
    assert_response :success
  end

end
