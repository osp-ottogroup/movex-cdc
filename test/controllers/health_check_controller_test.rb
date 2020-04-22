require 'test_helper'

class HealthCheckControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do

    ThreadHandling.get_instance.ensure_processing
    loop_count = 0
    while loop_count < 10 do                                                  # wait up to x seconds for processing of event_logs records
      loop_count += 1
      event_logs = TableLess.select_one("SELECT COUNT(*) FROM Event_Logs")
      break if event_logs == 0                                                # All records processed, no need to wait anymore
      sleep 1
    end

    get "/health_check", as: :json
    Rails.logger.info @response.body
    assert_response :conflict, '409 (conflict) expected because no worker threads are active'

    assert_raises(RuntimeError, 'second check should fail within same second') do
      get "/health_check", as: :json
    end

    ThreadHandling.get_instance.shutdown_processing
  end

end
