require 'test_helper'

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "Empty current thread variables" do
    assert_nil Thread.current[:current_user],           'Current user should be nil outside request processing'
    assert_nil Thread.current[:current_client_ip_info], 'Current client IP info should be nil outside request processing'
  end
end
