require 'test_helper'

class TableInitializationTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "get_instance" do
    instance = TableInitialization.get_instance
    assert instance.instance_of?(TableInitialization), log_on_failure('should return instance of class')
  end

  # Run the trigger generation with execution of initialization for victim1_table
  test "add_table_initialization" do
    run_test = proc do |key_handling|
      exec_victim_sql "DELETE FROM #{victim_schema_prefix}#{victim1_table.name}"
      test_record_count = 20
      insert_victim1_records(number_of_records_to_insert: test_record_count, last_max_id: 0)
      event_logs_before_test = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"

      case MovexCdc::Application.config.db_type
      when 'ORACLE' then
        sleep 1
        Database.execute "UPDATE Tables SET Topic=Topic"                          # ensure SCN is incremented at least once to prevent from ORA-01466 at update
        sleep 1
        Database.select_all "SELECT * FROM #{victim_schema_prefix}#{victim1_table.name}"  # Dummy read to prevent from ORA-01466
        Database.execute "UPDATE Tables SET Topic=Topic"                          # ensure SCN is incremented at least once to prevent from ORA-01466 at update
        sleep 2
      end

      # Ensure that initialization is started as part of trigger generation
      Table.find(GlobalFixtures.victim1_table.id).update!(yn_initialization: 'Y')

      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)

      assert_instance_of Hash, result, log_on_failure('Should return result of type Hash')
      result.assert_valid_keys(:successes, :errors, :load_sqls)
      assert_equal 0, result[:errors].count, log_on_failure('Should not return errors from trigger generation')

      ti_instance = TableInitialization.get_instance
      assert_equal 0, ti_instance.init_requests_count(raise_exception_if_locked: false), log_on_failure('Request should not be waiting')
      max_loop = 0
      while (ti_instance.init_requests_count(raise_exception_if_locked: false) > 0 ||
        ti_instance.running_threads_count(raise_exception_if_locked: false) > 0 ) &&
            max_loop < 20
        max_loop += 1
        Rails.logger.debug('TableInitializationTest.add_table_initialization') { "Waiting for pending initialization threads"}
        sleep 1
      end

      assert_equal 0, ti_instance.init_requests_count(raise_exception_if_locked: false), log_on_failure('All requests should be started')
      assert_equal 0, ti_instance.running_threads_count(raise_exception_if_locked: false), log_on_failure('All requests should be finished')

      event_logs_after_test = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
      assert_equal test_record_count, event_logs_after_test-event_logs_before_test, log_on_failure('Content of VICTIM1 should be initially loaded to Event_Logs')

      remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Regular processing of all records')
      assert_equal 0, remaining_event_log_count, log_on_failure('All Records from Event_Logs should be processed and deleted now')
    end

    key_handling_options.each do |keyhandling|
      run_with_current_user {
        current_table = Table.find(victim1_table.id)
        unless current_table.update(kafka_key_handling: keyhandling[:kafka_key_handling],
                                    fixed_message_key:  keyhandling[:fixed_message_key],
                                    key_expression:     keyhandling[:key_expression],
                                    yn_record_txid:     keyhandling[:yn_record_txid],
                                    lock_version:       current_table.lock_version
        )
          raise current_table.errors.full_messages
        end
        run_test.call(keyhandling)
      }
    end
  end
end
