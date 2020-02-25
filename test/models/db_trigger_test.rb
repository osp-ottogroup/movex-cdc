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

  test "find_by_table_id_and_trigger_name" do
    trigger = DbTrigger.find_by_table_id_and_trigger_name(4, 'Trixx_Victim1_I')
    assert_not_equal(nil, trigger, 'Should find the trigger in victim schema')
  end

  test "generate_triggers" do
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

    expected_event_logs = 8 + 1                                   # created Event_Logs-records by trigger + existing from fixture

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (1, 'Record1', 'Y', SYSDATE, LOCALTIMESTAMP, HexToRaw('FFFF'), SYSTIMESTAMP
      )"
      )
      rownum = 'RowNum'
    when 'SQLITE' then
      exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Name, Char_Name, Date_Val, TS_Val, RAW_VAL, TSTZ_Val)
      VALUES (1, 'Record1', 'Y', '2020-02-01T12:20:22', '2020-02-01T12:20:22.999999+01:00', 'FFFF', '2020-02-01T12:20:22.999999+01:00'
      )"
      )
      rownum = 'row_number() over ()'
    else
      raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end

    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name) VALUES (2, 45.375, 'Record2')")
    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Num_Val, Name) SELECT 2+#{rownum}, 48.375, 'Recordx' FROM #{victim_schema_prefix}#{tables(:victim1).name}")
    exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = 'Record3', RowID_Val = RowID WHERE ID = 3")
    exec_victim_sql(@victim_connection, "UPDATE #{victim_schema_prefix}#{tables(:victim1).name}  SET Name = 'Record4' WHERE ID = 4")
    exec_victim_sql(@victim_connection, "DELETE FROM #{victim_schema_prefix}#{tables(:victim1).name} WHERE ID IN (1, 2)")

    # Next record should not generate record in Event_Logs
    exec_victim_sql(@victim_connection, "INSERT INTO #{victim_schema_prefix}#{tables(:victim1).name} (ID, Name) VALUES (5, 'EXCLUDE FILTER')")

    real_event_logs     = TableLess.select_one "SELECT COUNT(*) FROM Event_Logs"
    assert_equal(expected_event_logs, real_event_logs, 'Previous operation should create x records in Event_Logs')

    # Dump Event_Logs
    TableLess.select_all("SELECT * FROM Event_Logs").each do |e|
      puts e['payload']
    end
  end

end
