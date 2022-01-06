require 'test_helper'

class TableInitializationTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "get_instance" do
    instance = TableInitialization.get_instance
    assert instance.instance_of?(TableInitialization), 'should return instance of class'
  end

  test "add_table_initialization" do
    test_record_count = 20
    event_logs_before_test = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    insert_victim1_records(number_of_records_to_insert: test_record_count, last_max_id: 0)

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.execute "BEGIN\nCOMMIT;\nCOMMIT;\nEND;"                          # ensure SCN is incremented at least once to prevent from ORA-01466 at update
      sleep 1
      Database.select_all "SELECT * FROM #{victim_schema_prefix}#{victim1_table.name}"  # Dummy read to prevent from ORA-01466
      Database.execute "BEGIN\nUPDATE Tables SET Topic=Topic;\nCOMMIT;\nEND;"                          # ensure SCN is incremented at least once to prevent from ORA-01466 at update
      sleep 1
    end

    # Ensure that initialization is started as part of trigger generation
    Table.find(GlobalFixtures.victim1_table.id).update!(yn_initialization: 'Y')

    result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id, user_options: user_options_4_test)

    assert_instance_of(Hash, result, 'Should return result of type Hash')
    result.assert_valid_keys(:successes, :errors, :load_sqls)
    assert_equal(0, result[:errors].count, 'Should not return errors from trigger generation')

    ti_instance = TableInitialization.get_instance
    assert_equal(0, ti_instance.init_requests_count(raise_exception_if_locked: false), 'Request should not be waiting')
    max_loop = 0
    while (ti_instance.init_requests_count(raise_exception_if_locked: false) > 0 ||
      ti_instance.running_threads_count(raise_exception_if_locked: false) > 0 ) &&
      max_loop < 20
      max_loop += 1
      sleep 1
    end

    assert_equal(0, ti_instance.init_requests_count(raise_exception_if_locked: false), 'All requests should be started')
    assert_equal(0, ti_instance.running_threads_count(raise_exception_if_locked: false), 'All requests should be finished')

    event_logs_after_test = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
    assert_equal(test_record_count, event_logs_after_test-event_logs_before_test, 'Content of VICTIM1 should be initially loaded to Event_Logs')

    remaining_event_log_count = process_eventlogs(max_wait_time: 20, expected_remaining_records: 0, title: 'Regular processing of all records')
    assert_equal 0, remaining_event_log_count, 'All Records from Event_Logs should be processed and deleted now'

  end


end

