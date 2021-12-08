require 'test_helper'

class ServerControlControllerTest < ActionDispatch::IntegrationTest
  test "should get get_log_level" do
    get "/server_control/get_log_level", headers: jwt_header, as: :json
    assert_response :success
  end


  test "should post set_log_level" do
    post "/server_control/set_log_level", headers: jwt_header, params: { log_level: 'ERROR'}, as: :json
    assert_response :unauthorized

    post "/server_control/set_log_level", headers: jwt_header(@jwt_admin_token), params: { log_level: 'ERROR'}, as: :json
    assert_response :success
    assert Rails.logger.level == 3, 'Log level should be set to ERROR now'

    # reset level to DEBUG
    post "/server_control/set_log_level", headers: jwt_header(@jwt_admin_token), params: { log_level: 'DEBUG'}, as: :json
    assert_response :success
    assert Rails.logger.level == 0, 'Log level should be set to DEBUG now'

  end

  test "should get get_worker_threads_count" do
    get "/server_control/get_worker_threads_count", headers: jwt_header, as: :json
    assert_response :success

    assert_equal @response.body, "{\"worker_threads_count\":#{MovexCdc::Application.config.initial_worker_threads}}"
  end

  test "should post set_worker_threads_count" do
    ThreadHandling.get_instance.ensure_processing                               # Start worker threads, regularly not started for test

    post "/server_control/set_worker_threads_count", headers: jwt_header, params: { worker_threads_count: 3}, as: :json
    assert_response :unauthorized

    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 5}, as: :json
    assert_response :success
    assert_equal 5, ThreadHandling.get_instance.thread_count, 'There should run x threads now'

    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 2}, as: :json
    assert_response :success
    assert_equal 2, ThreadHandling.get_instance.thread_count, 'There should run x threads now'

    # Value too large, should return error
    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 200000}, as: :json
    assert_response :internal_server_error

    Thread.new do                                                               # execute request in background, so the next request should fail
      post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 6}, as: :json
    end
    sleep 1                                                                     # let thread start
    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 4}, as: :json
    assert_response :internal_server_error
    assert_equal 6, ThreadHandling.get_instance.thread_count, 'There should run 6 threads now because the async request was first'

    ThreadHandling.get_instance.shutdown_processing                             # Stop worker threads to restore normal test state
  end

  test "should post set_max_transaction_size" do
    ThreadHandling.get_instance.ensure_processing                               # Start worker threads, regularly not started for test

    post "/server_control/set_max_transaction_size", headers: jwt_header, params: { max_transaction_size: 1000}, as: :json
    assert_response :unauthorized

    post "/server_control/set_max_transaction_size", headers: jwt_header(@jwt_admin_token), params: { max_transaction_size: 1000}, as: :json
    assert_response :success
    assert_equal 1000, MovexCdc::Application.config.max_transaction_size, 'Should be set in config'

    post "/server_control/set_max_transaction_size", headers: jwt_header(@jwt_admin_token), params: { max_transaction_size: 5000}, as: :json
    assert_response :success
    assert_equal 5000, MovexCdc::Application.config.max_transaction_size, 'Should be set in config'

  end

end
