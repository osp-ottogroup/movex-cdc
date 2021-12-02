require 'test_helper'

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "should get html doc" do
    get "/movex-cdc.html", as: :html
    assert_response :success
  end

  test "should get pdf doc" do
    get "/movex-cdc.pdf", as: :html
    assert_response :success
  end

end
