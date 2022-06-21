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
    assert Rails.logger.level == 3, log_on_failure('Log level should be set to ERROR now')

    # reset level to DEBUG
    post "/server_control/set_log_level", headers: jwt_header(@jwt_admin_token), params: { log_level: 'DEBUG'}, as: :json
    assert_response :success
    assert Rails.logger.level == 0, log_on_failure('Log level should be set to DEBUG now')

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
    assert_equal 5, ThreadHandling.get_instance.thread_count, log_on_failure('There should run x threads now')

    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 2}, as: :json
    assert_response :success
    assert_equal 2, ThreadHandling.get_instance.thread_count, log_on_failure('There should run x threads now')

    # Value too large, should return error
    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 200000}, as: :json
    assert_response :internal_server_error

    expected_worker_count = 6                                                   # expected number of workers after successful change
    Thread.new do                                                               # execute request in background, so the next request should fail
      post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: expected_worker_count}, as: :json
    end
    sleep 0.2                                                                   # let thread start but be fast enough before thread has finished
    post "/server_control/set_worker_threads_count", headers: jwt_header(@jwt_admin_token), params: { worker_threads_count: 4}, as: :json
    assert_response :internal_server_error

    # Wait until the async setting of expected_worker_count has finished
    waited_loop = 0
    while ThreadHandling.get_instance.thread_count != expected_worker_count && waited_loop < 10
      waited_loop += 1
      Rails.logger.debug('ServerControllerTest.should post set_worker_threads_count') { "Waiting for ThreadHandling.get_instance.thread_count to be expected"}
      sleep 1
    end

    assert_equal expected_worker_count, ThreadHandling.get_instance.thread_count, log_on_failure("There should run #{expected_worker_count} threads now because the async request was first")

    ThreadHandling.get_instance.shutdown_processing                             # Stop worker threads to restore normal test state
  end

  test "should post set_max_transaction_size" do
    ThreadHandling.get_instance.ensure_processing                               # Start worker threads, regularly not started for test

    post "/server_control/set_max_transaction_size", headers: jwt_header, params: { max_transaction_size: 1000}, as: :json
    assert_response :unauthorized

    post "/server_control/set_max_transaction_size", headers: jwt_header(@jwt_admin_token), params: { max_transaction_size: 1000}, as: :json
    assert_response :success
    assert_equal 1000, MovexCdc::Application.config.max_transaction_size, log_on_failure('Should be set in config')

    post "/server_control/set_max_transaction_size", headers: jwt_header(@jwt_admin_token), params: { max_transaction_size: 5000}, as: :json
    assert_response :success
    assert_equal 5000, MovexCdc::Application.config.max_transaction_size, log_on_failure('Should be set in config')

  end

  test "reprocess final errors" do
    @final_errors_victim1 = 5
    @final_errors_victim2 = 7
    @final_errors_tables  = 3

    def create_final_errors
      Database.execute "DELETE FROM Event_Log_Final_Errors"
      Database.execute "DELETE FROM Event_Logs"
      final_errors_id = 0
      [
        {amount: @final_errors_victim1, table_id: victim1_table.id},
        {amount: @final_errors_victim2, table_id: victim2_table.id},
        {amount: @final_errors_tables,  table_id: tables_table.id},
      ].each do |p|
        1.upto(p[:amount]) do |v|
          Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (:id, :table_id, 'I', 'HUGO', '{}', :created_at, :error_time, 'Test-Error to delete')
                   ", binds: {id: final_errors_id+=1, table_id: p[:table_id], created_at: (p[:amount]-v).day.ago, error_time: (p[:amount]-v).day.ago}
        end
      end
      Database.execute "COMMIT" if MovexCdc::Application.config.db_type == 'ORACLE'
    end

    post "/server_control/reprocess_final_errors", headers: jwt_header, as: :json
    assert_response :unauthorized

    create_final_errors
    post "/server_control/reprocess_final_errors", headers: jwt_header(@jwt_admin_token), as: :json
    assert_response :success, log_on_failure('All final errors should be processed')
    assert_equal 0, Database.select_one("SELECT COUNT(*) FROM Event_Log_Final_Errors"), log_on_failure('All final errors should be removed from Event_Log_Final_Errors now')
    assert_equal @final_errors_victim1+@final_errors_victim2+@final_errors_tables, Database.select_one("SELECT COUNT(*) FROM Event_Logs"), log_on_failure('All final errors should be in Event_Logs now')

    create_final_errors
    expected_event_logs = Database.select_one("SELECT COUNT(*) FROM Event_Log_Final_Errors f JOIN Tables t ON t.ID = f.Table_ID WHERE t.Schema_ID = :schema_id", {schema_id: victim1_table.schema_id})
    post "/server_control/reprocess_final_errors", headers: jwt_header(@jwt_admin_token), params: {schema: victim1_table.schema.name}, as: :json
    assert_response :success, log_on_failure('All final errors of schema should be processed')
    assert_equal 0, Database.select_one("SELECT COUNT(*) FROM Event_Log_Final_Errors f JOIN Tables t ON t.ID = f.Table_ID WHERE t.Schema_ID = :schema_id", {schema_id: victim1_table.schema_id}), log_on_failure('All final errors of schema should be removed from Event_Log_Final_Errors now')
    assert_equal expected_event_logs, Database.select_one("SELECT COUNT(*) FROM Event_Logs"), log_on_failure('All final errors of schema should be in Event_Logs now')

    create_final_errors
    post "/server_control/reprocess_final_errors", headers: jwt_header(@jwt_admin_token), params: {schema: victim1_table.schema.name, table_name: victim1_table.name}, as: :json
    assert_response :success, log_on_failure('All final errors of table should be processed')
    assert_equal 0, Database.select_one("SELECT COUNT(*) FROM Event_Log_Final_Errors WHERE Table_ID = :table_id", {table_id: victim1_table.id}), log_on_failure('All final errors of table should be removed from Event_Log_Final_Errors now')
    assert_equal @final_errors_victim1, Database.select_one("SELECT COUNT(*) FROM Event_Logs"), log_on_failure('All final errors of table should be in Event_Logs now')

    Database.execute "DELETE FROM Event_Logs"                                   # Remove unprocessable events
  end
end
