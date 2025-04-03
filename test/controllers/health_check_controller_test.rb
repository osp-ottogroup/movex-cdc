require 'test_helper'

class HealthCheckControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do

    ThreadHandling.get_instance.ensure_processing
    SystemValidationJob.new.reset_job_warnings(3600)                            # Suppress health status due to not running job within time
    loop_count = 0
    while loop_count < 10 do                                                    # wait up to x seconds for processing of event_logs records
      loop_count += 1
      event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Logs")
      break if event_logs == 0                                                  # All records processed, no need to wait anymore
      Rails.logger.debug('HealthCheckControllerTest.should get index') { "Waiting for Event_Logs to be empty"}
      sleep 1
    end

    get "/health_check", as: :json
    Rails.logger.info('HealthCheckControllerTest.should get index'){ @response.body }
    if MovexCdc::Application.config.initial_worker_threads == ThreadHandling.get_instance.thread_count
      if @response.status != 200                                                 # Thread possibly not yet initialized (pending Kafka connection etc.
        sleep 2
        get "/health_check", as: :json                                          # Do it again
        Rails.logger.info('HealthCheckControllerTest.should get index'){ "Repeated request after sleep. Response:\n#{@response.body}" }
      end
      assert_response :success, log_on_failure("200 (success) expected because all worker threads are active, but is #{@response.response_code}")
    else
      assert_response :conflict, log_on_failure("409 (conflict) expected because not all worker threads are active, but is #{@response.response_code}")
    end
    sleep 1                                                                     # Ensure next request ends with 200

    get "/health_check", as: :json                                              # warmup health check to ensure next response within one second
    assert_response :success, log_on_failure('This request should succeed')
    get "/health_check", as: :json
    assert_response :internal_server_error, log_on_failure('second check should fail within same second')
    get "/health_check", headers: jwt_header, as: :json                                              # warmup health check to ensure next response within one second
    assert_response :success, log_on_failure('This request within the same second should succeed because it is authorized with valid JWT')

    sleep 2                                                                     # prevent from double call exception
    begin
      raise "This is a  problem with a job"
    rescue Exception => e
      SystemValidationJob.new.reset_job_warnings(60)
      SystemValidationJob.new.add_execption_to_job_warning(e)
    end
    get "/health_check", as: :json
    assert_response :conflict, log_on_failure('should report job problem')

    ThreadHandling.get_instance.shutdown_processing
  end

  test "should get status" do
    get "/health_check/status", as: :json
    assert_response :unauthorized, log_on_failure('No access without JWT')

    get "/health_check/status", headers: jwt_header, as: :json
    assert_response :success, log_on_failure('should get status with JWT')
  end

  test "should get log_file" do
    get "/health_check/log_file", as: :json
    assert_response :unauthorized, log_on_failure('No access without JWT')

    get "/health_check/log_file", headers: jwt_header, as: :json
    assert_response :success, log_on_failure('should get log file with JWT')
  end

  test "should get config_info" do
    get health_check_config_info_url, headers: jwt_header, as: :json
    assert_response :success
  end
end
