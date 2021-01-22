require 'test_helper'

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "should get html doc" do
    get "/trixx.html", as: :html
    assert_response :success
  end

  test "should get pdf doc" do
    get "/trixx.pdf", as: :html
    assert_response :success
  end

end
