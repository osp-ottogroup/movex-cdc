require 'test_helper'

class StatisticEventLogFinalErrorsTest < ActiveSupport::TestCase
  test "retrieve table Event_Log_Final_Errors statistics" do

    table_name = "StatisticEventLogFinalErrorsTest_#{Process.pid}_#{(Time.now.to_f * 1000).to_i}"
    table_id = -((Time.now.to_f * 1000).to_i % 1_000_000) - 1000

    run_with_current_user do
      StatisticEventLogFinalErrors.remove_instance

      # Create a certain table used as reference in event log final error data records
      Database.execute "DELETE FROM Tables WHERE name = :name", binds: {name: table_name}
      Database.execute "INSERT INTO Tables (id,schema_id,name,kafka_key_handling,yn_hidden,lock_version,created_at,updated_at,yn_record_txid,yn_initialization,yn_initialize_with_flashback,yn_add_cloudevents_header,yn_payload_pkey_only)
                    SELECT
                      :id AS id
                      ,MIN(ID) AS schema_id
                      ,:name AS name
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
                      Schemas", binds: {id: table_id, name: table_name, created_at: 1.minutes.ago, updated_at: 1.minutes.ago}
      @schema_name = Table.find(table_id).schema.name

      # Create test data records in table Event_Log_Final_Errors
      Database.execute "DELETE FROM Event_Log_Final_Errors WHERE Table_ID = :table_id", binds: {table_id: table_id}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (:id, :table_id, 'I', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation INSERT: Event Log Final Error entry')
                   ", binds: {id: table_id * 10 - 1, table_id: table_id, created_at: (Time.now - (10 * 60)), error_time: (Time.now - (10 * 60))}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (:id, :table_id, 'I', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation INSERT: Event Log Final Error entry')
                   ", binds: {id: table_id * 10 - 2, table_id: table_id, created_at: (Time.now - (20 * 60)), error_time: (Time.now - (20 * 60))}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (:id, :table_id, 'D', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation DELETE: Event Log Final Error entry')
                   ", binds: {id: table_id * 10 - 3, table_id: table_id, created_at: (Time.now - (50 * 60)), error_time: (Time.now - (50 * 60))}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (:id, :table_id, 'I', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation INSERT: Event Log Final Error entry')
                   ", binds: {id: table_id * 10 - 4, table_id: table_id, created_at: (Time.now - (130 * 60)), error_time: (Time.now - (130 * 60))}
      Database.execute "INSERT INTO Event_Log_Final_Errors (ID, Table_ID, Operation, DBUser, Payload, Created_At, Error_Time, Error_Msg)
                    VALUES (:id, :table_id, 'D', 'HUGO', '\"new\": { \"ID\": 1}', :created_at, :error_time, 'Operation DELETE: Event Log Final Error entry')
                   ", binds: {id: table_id * 10 - 5, table_id: table_id, created_at: (Time.now - (130 * 60)), error_time: (Time.now - (130 * 60))}

      # Force refresh and retrieve object containing most recent statistic of table Event_Log_Final_Errors
      StatisticEventLogFinalErrors.get_instance.refresh_statistic
      statistics = StatisticEventLogFinalErrors.get_instance.get_statistic

      # Consider only rows of this dedicated test table to isolate from concurrent writers.
      table_statistics = statistics.select do |record|
        record.schema_name == @schema_name && record.table_name == table_name
      end

      # Expected test result #1: exactly two items are returned for this test table
      assert_equal 2, table_statistics.length

      # Expected test result #2 and #3: counts per operation independent from global order
      operation_counts = table_statistics.to_h { |row| [row.operation, row.current_value.to_i] }
      assert_equal({'D' => 2, 'I' => 3}, operation_counts)

      Database.execute "DELETE FROM Event_Log_Final_Errors WHERE Table_ID = :table_id", binds: {table_id: table_id} if table_id
      Database.execute "DELETE FROM Tables WHERE id = :id", binds: {id: table_id} if table_id
    end
  ensure
    StatisticEventLogFinalErrors.remove_instance
  end
end