require 'test_helper'

class DbTriggerTest < ActiveSupport::TestCase

  setup do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)
    @user_options = { user_id: users(:one).id, client_ip_info: '10.10.10.10'}

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      # prevent from ORA-01466
      Database.execute "BEGIN\nCOMMIT;\nEND;"                               # ensure SCN is incremented at least once
    end

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
    triggers = DbTrigger.find_all_by_table(tables(:victim1).schema_id, tables(:victim1).id, tables(:victim1).schema.name, tables(:victim1).name)
    assert_equal(1, triggers.count, 'Should find triggers for table with valid trixx trigger names')
  end

  test "find_by_table_id_and_trigger_name" do
    victim1_table = tables(:victim1)
    trigger = DbTrigger.find_by_table_id_and_trigger_name(victim1_table.id, DbTrigger.build_trigger_name(victim1_table.schema_id, victim1_table.id, 'I'))
    assert_not_equal(nil, trigger, 'Should find the trigger in victim schema')
  end

  test "generate_triggers" do
    # Execute test for each key handling type
    [
        {kafka_key_handling: 'N', fixed_message_key: nil, yn_record_txid: 'N'},
        {kafka_key_handling: 'P', fixed_message_key: nil, yn_record_txid: 'Y'},
        {kafka_key_handling: 'F', fixed_message_key: 'hugo', yn_record_txid: 'N'},
        {kafka_key_handling: 'T', fixed_message_key: nil, yn_record_txid: 'Y'},
    ].each do |key|
      # Modify tables with attributes
      [tables(:victim1), tables(:victim2)].each do |table|
        unless table.update(kafka_key_handling: key[:kafka_key_handling], fixed_message_key: key[:fixed_message_key], yn_record_txid: key[:yn_record_txid])
          raise table.errors.full_messages
        end
      end

      exec_victim_sql(@victim_connection, "DELETE FROM #{victim_schema_prefix}#{tables(:victim1).name}")  # Ensure record count starts at 0

      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema_id, user_options: @user_options)

      assert_instance_of(Hash, result, 'Should return result of type Hash')
      result.assert_valid_keys(:successes, :errors, :load_sqls)

      result[:errors].each do |e|
        puts "Trigger #{e[:trigger_name]} #{e[:exception_class]}: #{e[:exception_message]}"
      end

      created_trigger_names = result[:successes].select{|x| x[:sql]['CREATE']}.map{|x| x[:trigger_name]}
      assert_equal 2, created_trigger_names.select{|x| x['_I']}.length, 'Should have created x insert trigger'
      assert_equal 2, created_trigger_names.select{|x| x['_U']}.length, 'Should have created x update trigger'
      assert_equal 2, created_trigger_names.select{|x| x['_D']}.length, 'Should have created x delete trigger'

      assert_not_nil result[:successes][0][:table_id],           ':table_id in successes result should be set for trigger'
      assert_not_nil result[:successes][0][:table_name],         ':table_name in successes result should be set for trigger'
      assert_not_nil result[:successes][0][:trigger_name],       ':trigger_name in successes result should be set for trigger'
      assert_not_nil result[:successes][0][:sql],                ':sql in successes result should be set for trigger'


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

      # second run of trigger generation should not touch the already existing triggers
      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema_id, user_options: @user_options)
      assert_equal 0, result[:successes].length,  '2nd run should not touch the existing triggers'
      assert_equal 0, result[:errors].length,     '2nd run should not have errors'

      fixture_event_logs     = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
      event_logs_to_create = 20
      expected_event_logs = event_logs_to_create + fixture_event_logs           # created Event_Logs-records by trigger + existing from fixture

      create_event_logs_for_test(event_logs_to_create)

      real_event_logs     = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
      assert_equal(expected_event_logs, real_event_logs, 'Previous operation should create x records in Event_Logs')

      assert EventLog.last!.transaction_id.nil? ^ (key[:yn_record_txid] == 'Y'), "Transaction-ID must be filled only if requested! yn_record_txid=#{key[:yn_record_txid]}"

      # Dump Event_Logs and check JSON structure
      Rails.logger.info "======== Dump all event_logs ========="
      Database.select_all("SELECT * FROM Event_Logs").each do |e|
        Rails.logger.info e
        JSON.parse("{ #{e['payload']} }")                                       # Check in generated JSON is valid
      end

    end
  end

  test "generate_triggers dry run" do
    # Execute test for each key handling type
    [
      {kafka_key_handling: 'N', fixed_message_key: nil, yn_record_txid: 'N'},
      {kafka_key_handling: 'P', fixed_message_key: nil, yn_record_txid: 'Y'},
      {kafka_key_handling: 'F', fixed_message_key: 'hugo', yn_record_txid: 'N'},
      {kafka_key_handling: 'T', fixed_message_key: nil, yn_record_txid: 'Y'},
    ].each do |key|
      # Modify tables with attributes
      [tables(:victim1), tables(:victim2)].each do |table|
        unless table.update(kafka_key_handling: key[:kafka_key_handling], fixed_message_key: key[:fixed_message_key], yn_record_txid: key[:yn_record_txid])
          raise table.errors.full_messages
        end
      end

      existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema_id)

      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema_id, user_options: @user_options, dry_run: true)

      existing_triggers_after = DbTrigger.find_all_by_schema_id(victim_schema_id)

      assert_equal existing_triggers_before.count, existing_triggers_after.count, 'existing triggers should not be touched by dry run'

      assert_instance_of(Hash, result, 'Should return result of type Hash')
      result.assert_valid_keys(:successes, :errors, :load_sqls)
    end
  end


  test "generate erroneous trigger" do
    condition = Condition.where(table_id: tables(:victim1).id, operation: 'I').first
    original_filter = condition.filter
    condition.update!(filter: "NOT EXECUTABLE SQL")  # Set a condition that causes compile error for trigger
    result = DbTrigger.generate_schema_triggers(schema_id: victim_schema_id, user_options: @user_options)
    assert_equal 1, result[:errors].count, 'Should result in compile error for one trigger'
    assert_not_nil result[:errors][0][:table_id],           ':table_id in error result should be set for trigger'
    assert_not_nil result[:errors][0][:table_name],         ':table_name in error result should be set for trigger'
    assert_not_nil result[:errors][0][:trigger_name],       ':trigger_name in error result should be set for trigger'
    assert_not_nil result[:errors][0][:exception_class],    ':exception_class in error result should be set for trigger'
    assert_not_nil result[:errors][0][:exception_message],  ':exception_message in error result should be set for trigger'
    assert_not_nil result[:errors][0][:sql],                ':sql in error result should be set for trigger'

    Rails.logger.debug("Reset condition to '#{original_filter}'")
    condition.update!(filter: original_filter)                                  # reset valid entry
    DbTrigger.generate_schema_triggers(schema_id: victim_schema_id, user_options: @user_options) # Create trigger again to raise DDL that commits the update on condition
  end

  test "generate trigger with initialization" do
    org_yn_initialization = tables(:victim1).yn_initialization
    create_event_logs_for_test(20)                                              # create some records in victim1 before yn_initialization is set
    victim_record_count = Database.select_one "SELECT COUNT(*) FROM #{victim_schema_prefix}#{tables(:victim1).name}" # requires select-Grant
    max_victim_id = Database.select_one "SELECT MAX(ID) FROM #{victim_schema_prefix}#{tables(:victim1).name}"
    second_max_victim_id = Database.select_one "SELECT MAX(ID) FROM #{victim_schema_prefix}#{tables(:victim1).name} WHERE ID != :max_id", max_id: max_victim_id
    insert_condition = case Trixx::Application.config.trixx_db_type
                       when 'ORACLE' then ":new.ID != #{second_max_victim_id}"
                       when 'SQLITE' then "new.ID != #{second_max_victim_id}"
                       end
    [nil, "ID != #{max_victim_id}"].each do |init_filter|
      [nil, insert_condition].each do |condition_filter|  # condition filter should be valid for execution inside trigger
        condition         = Condition.where(table_id: tables(:victim1).id, operation: 'I').first
        original_condition_filter = condition.filter

        if condition_filter.nil?
          condition.destroy!
        else
          condition.update! filter: condition_filter
        end

        Table.find(tables(:victim1).id).update!(yn_initialization: 'Y', initialization_filter: init_filter) # set a init filter for one record
        filtered_records_count = 0
        filtered_records_count += 1 unless init_filter.nil?
        filtered_records_count += 1 unless condition_filter.nil?
        event_logs_count_before = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
        result = DbTrigger.generate_schema_triggers(schema_id: victim_schema_id, user_options: @user_options)
        assert_equal 1, result[:load_sqls].length, 'load SQLs should be generated'

        # Wait for successful initialization

        loop_count = 0
        table_init = TableInitialization.get_instance
        while (table_init.running_threads_count > 0 || table_init.init_requests_count > 0) && loop_count < 20 do
          loop_count += 1
          sleep 1
        end
        assert_equal 0, table_init.init_requests_count, 'There should not be unprocessed requests'
        assert_equal 0, table_init.running_threads_count, 'There should not be running threads'


        event_logs_count_after = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
        assert_equal(victim_record_count - filtered_records_count, event_logs_count_after - event_logs_count_before,
                     'Each record in Victim1 should have caused an additional init record in Event_Logs except x filtered records')

        if condition_filter.nil?
          Condition.new(condition.attributes).save!                             # recreate the dropped condition
        else
          condition.update!(filter: original_condition_filter)                  # restore original
        end
      end
    end


    tables(:victim1).update!(yn_initialization: org_yn_initialization)          # restore original state
  end
end
