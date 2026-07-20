require 'test_helper'

class StatisticEventLogFinalErrorsTest < ActiveSupport::TestCase
  test "retrieve table Event_Log_Final_Errors statistics" do
    run_with_current_user do
      StatisticEventLogFinalErrors.remove_instance

      # Create a certain table used as reference in event log final error data records
      Database.execute "DELETE FROM Tables WHERE name = 'StatisticEventLogFinalErrorsTest'"
      Database.execute "INSERT INTO Tables (id,schema_id,name,kafka_key_handling,yn_hidden,lock_version,created_at,updated_at,yn_record_txid,yn_initialization,yn_initialize_with_flashback,yn_add_cloudevents_header,yn_payload_pkey_only)
                    SELECT
                      -100 AS id
                      ,MIN(ID) AS schema_id
                      ,'StatisticEventLogFinalErrorsTest' AS name
                      ,'N' AS kafka_key_handling
                      ,'N' AS yn_hidden
                      ,0 AS lock_version
                      ,:created_at AS created_at
                      ,:updated_at AS updated_at
                      ,'N' AS yn_record_txid
                      ,'N' AS yn_initialization
                      ,'Y' AS yn_initialize_with_flashback
                      ,'N' AS yn_add_cloudevents_header
                      ,'N' AS yn_payload_pkey_only
                    FROM
                      Schemas", binds: {created_at: 1.minutes.ago, updated_at: 1.minutes.ago}
      @schema_name = Database.select_one("
                    SELECT
                      sch.name AS schema_name
                    FROM
                      Tables tab
                      INNER JOIN Schemas sch
                        ON sch.id = tab.schema_id
                    WHERE
                      tab.id = -100
                      AND tab.name = 'StatisticEventLogFinalErrorsTest'")

      # Create test data records in table Event_Log_Final_Errors
      Database.execute "DELETE FROM Event_Log_Final_Errors"
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-1, -100, 'I', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation INSERT: Visible Event Log Final Error entry')
                   ", binds: {created_at: 10.minutes.ago, error_time: 10.minutes.ago}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-2, -100, 'I', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation INSERT: Visible Event Log Final Error entry')
                   ", binds: {created_at: 20.minutes.ago, error_time: 20.minutes.ago}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-3, -100, 'D', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation DELETE: Visible Event Log Final Error entry')
                   ", binds: {created_at: 50.minutes.ago, error_time: 50.minutes.ago}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-4, -100, 'I', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation INSERT: Non Visible Event Log Final Error entry')
                   ", binds: {created_at: 130.minutes.ago, error_time: 130.minutes.ago}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (-5, -100, 'D', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation DELETE: Non Visible Event Log Final Error entry')
                   ", binds: {created_at: 130.minutes.ago, error_time: 130.minutes.ago}

      # Retrieve object containing most recent statistic of table Event_Log_Final_Errors
      statistics = StatisticEventLogFinalErrors.get_instance.get_statistic

      # Expected test result #1: 2 items are returned by the database
      assert_equal 2, statistics.length
      # Expected test result #2: 1st item relates to deletion / 2nd (last) item relates to insertion of records
      assert_equal @schema_name + '.StatisticEventLogFinalErrorsTest/D', statistics.first.schema_name + '.' + statistics.first.table_name + '/' + statistics.first.operation
      assert_equal @schema_name + '.StatisticEventLogFinalErrorsTest/I', statistics.last.schema_name + '.' + statistics.last.table_name + '/' + statistics.last.operation
      # Expected test result #3: 1st item relates to deletion of one record / 2nd (last) item relates to insertion of two records
      assert_equal 1, statistics.first.current_value
      assert_equal 2, statistics.last.current_value

      Database.execute "DELETE FROM Event_Log_Final_Errors"
      Database.execute "DELETE FROM Tables WHERE name = 'StatisticEventLogFinalErrorsTest'"
    end
  ensure
    StatisticEventLogFinalErrors.remove_instance
  end
end