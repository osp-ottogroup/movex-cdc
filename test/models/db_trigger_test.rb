require 'test_helper'

class DbTriggerTest < ActiveSupport::TestCase

  setup do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)
  end

  teardown do
    # Remove victim structures
    drop_victim_structures(@victim_connection)
    logoff_victim_connection(@victim_connection)
  end

  test "find_all_by_schema_id" do
    triggers = DbTrigger.find_all_by_schema_id(victim_schema_id)
    assert_equal(2, triggers.count, 'Should find the number of triggers in victim schema')
  end

  test "find_all_by_table" do
    triggers = DbTrigger.find_all_by_table(tables(:victim1).id, tables(:victim1).schema.name, tables(:victim1).name)
    assert_equal(1, triggers.count, 'Should find triggers for table with valid trixx trigger names')
  end

  test "find_by_table_id_and_trigger_name" do
    victim1_table = tables(:victim1)
    trigger = DbTrigger.find_by_table_id_and_trigger_name(victim1_table.id, DbTrigger.build_trigger_name(victim1_table.name, victim1_table.id, 'I'))
    assert_not_equal(nil, trigger, 'Should find the trigger in victim schema')
  end

  test "generate_triggers" do
    # Execute test for each key handling type
    [
        {kafka_key_handling: 'N', fixed_message_key: nil},
        {kafka_key_handling: 'P', fixed_message_key: nil},
        {kafka_key_handling: 'F', fixed_message_key: 'hugo'},
    ].each do |key|
      table = tables(:victim1)
      unless table.update(kafka_key_handling: key[:kafka_key_handling], fixed_message_key: key[:fixed_message_key])
        raise table.errors.full_messages
      end
      exec_victim_sql(@victim_connection, "DELETE FROM #{victim_schema_prefix}#{tables(:victim1).name}")  # Ensure record count starts at 0

      result = DbTrigger.generate_triggers(victim_schema_id)
      assert_instance_of(Hash, result, 'Should return result of type Hash')
      result.assert_valid_keys(:successes, :errors)

=begin
    puts "Successes:" if result[:successes].count > 0
    result[:successes].each do |s|
      puts s
    end
=end

      if result[:errors].count > 0
        puts "Errors:"
        result[:errors].each do |e|
          puts "#{e[:trigger_name]} #{e[:exception_class]}"
          puts "#{e[:exception_message]}"
          puts e[:sql]
        end
      end
      assert_equal(0, result[:errors].count, 'Should not return errors from trigger generation')

      assert_not_nil Schema.find(victim_schema_id).last_trigger_deployment, 'Timestamp of last successful trigger generation should be set'

      fixture_event_logs     = TableLess.select_one "SELECT COUNT(*) FROM Event_Logs"
      expected_event_logs = 8 + fixture_event_logs                                # created Event_Logs-records by trigger + existing from fixture

      case Trixx::Application.config.trixx_db_type
      when 'ORACLE' then
        date_val  = "SYSDATE"
        ts_val    = "LOCALTIMESTAMP"
        raw_val   = "HexToRaw('FFFF')"
        tstz_val  = "SYSTIMESTAMP"
        rownum    = "RowNum"
      when 'SQLITE' then
        date_val  = "'2020-02-01T12:20:22'"
        ts_val    = "'2020-02-01T12:20:22.999999+01:00'"
        raw_val   = "'FFFF'"
        tstz_val  = "'2020-02-01T12:20:22.999999+01:00'"
        rownum    = 'row_number() over ()'
      else
        raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
      end

      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (1, 1, 'Record1', 'Y', #{date_val}, #{ts_val}, #{raw_val}, #{tstz_val}
      )")


      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (2, 45.375, 'Record''2', #{date_val}, #{ts_val}, #{raw_val})")
      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) SELECT 2+#{rownum}, 48.375, '\"Recordx', Date_Val, TS_Val, RAW_VAL FROM #{victim_schema_prefix}#{tables(:victim1).name}")
      exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = 'Record3', RowID_Val = RowID WHERE ID = 3")
      exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = 'Record4' WHERE ID = 4")
      exec_victim_sql(@victim_connection, "DELETE FROM #{victim_schema_prefix}#{tables(:victim1).name} WHERE ID IN (1, 2)")

      # Next record should not generate record in Event_Logs
      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name, Date_Val, TS_Val, RAW_VAL) VALUES (5, 1, 'EXCLUDE FILTER', #{date_val}, #{ts_val}, #{raw_val})")

      real_event_logs     = TableLess.select_one "SELECT COUNT(*) FROM Event_Logs"
      assert_equal(expected_event_logs, real_event_logs, 'Previous operation should create x records in Event_Logs')

      # Dump Event_Logs
      Rails.logger.info "======== Dump all event_logs ========="
      TableLess.select_all("SELECT * FROM Event_Logs").each do |e|
        Rails.logger.info e
      end

    end
  end

end
