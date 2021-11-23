require 'test_helper'

class HealthCheckControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do

    ThreadHandling.get_instance.ensure_processing
    loop_count = 0
    while loop_count < 10 do                                                  # wait up to x seconds for processing of event_logs records
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      break if event_logs == 0                                                # All records processed, no need to wait anymore
      sleep 1
    end

    get "/health_check", as: :json
    Rails.logger.info @response.body
    if Trixx::Application.config.trixx_initial_worker_threads == ThreadHandling.get_instance.thread_count
      assert_response :success, "200 (success) expected because all worker threads are active, but is #{@response.response_code}"
    else
      assert_response :conflict, "409 (conflict) expected because not all worker threads are active, but is #{@response.response_code}"
    end

    get "/health_check", as: :json                                              # warmup health check to ensure next response within one second
    get "/health_check", as: :json
    assert_response :internal_server_error, 'second check should fail within same second'

    sleep 2                                                                     # prevent from double call exception
    begin
      raise "This is a  problem with a job"
    rescue Exception => e
      SystemValidationJob.new.reset_job_warnings(60)
      SystemValidationJob.new.add_execption_to_job_warning(e)
    end
    get "/health_check", as: :json
    assert_response :conflict, 'should report job problem'

    ThreadHandling.get_instance.shutdown_processing
  end

  test "should get status" do
    get "/health_check/status", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/health_check/status", headers: jwt_header, as: :json
    assert_response :success, 'should get status with JWT'
  end

  test "should get log_file" do
    get "/health_check/log_file", as: :json
    assert_response :unauthorized, 'No access without JWT'

    get "/health_check/log_file", headers: jwt_header, as: :json
    assert_response :success, 'should get log file with JWT'
  end

  test "should get config_info" do
    get health_check_config_info_url, headers: jwt_header, as: :json
    assert_response :success
  end
end
