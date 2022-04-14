require 'test_helper'

class DbTriggerTest < ActiveSupport::TestCase

  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "find_all_by_schema_id" do
    triggers = DbTrigger.find_all_by_schema_id(victim_schema.id)
    assert_equal 2, triggers.count, log_on_failure('Should find the number of triggers in victim schema')
  end

  test "find_all_by_table" do
    triggers = DbTrigger.find_all_by_table(victim1_table)
    assert_equal 2, triggers.count, log_on_failure('Should find triggers for table with valid MOVEX CDC trigger name prefix')

    result = run_with_current_user { DbTrigger.generate_schema_triggers(schema_id: victim_schema.id) }
    triggers = DbTrigger.find_all_by_table(victim1_table)
    assert_equal 3, triggers.count, log_on_failure('Should find triggers for table after trigger generation')
  end

  test "find_by_table_id_and_trigger_name" do
    trigger = DbTrigger.find_by_table_id_and_trigger_name(victim1_table.id, DbTrigger.build_trigger_name(victim1_table, 'I'))
    assert_not_equal nil, trigger, log_on_failure('Should find the trigger in victim schema')
  end

  test "generate_triggers" do
    run_with_current_user do
      # Execute test for each key handling type
      [
        {kafka_key_handling: 'N', fixed_message_key: nil, yn_record_txid: 'N'},
        {kafka_key_handling: 'P', fixed_message_key: nil, yn_record_txid: 'Y'},
        {kafka_key_handling: 'F', fixed_message_key: 'hugo', yn_record_txid: 'N'},
        {kafka_key_handling: 'T', fixed_message_key: nil, yn_record_txid: 'Y'},
      ].each do |key|
        # Modify tables with attributes
        [victim1_table, victim2_table].each do |table|
          current_table = Table.find(table.id)
          unless current_table.update(kafka_key_handling: key[:kafka_key_handling],
                                      fixed_message_key:  key[:fixed_message_key],
                                      yn_record_txid:     key[:yn_record_txid],
                                      lock_version:       current_table.lock_version
          )
            raise table.errors.full_messages
          end
        end

        exec_victim_sql("DELETE FROM #{victim_schema_prefix}#{victim1_table.name}")  # Ensure record count starts at 0

        result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)

        assert_instance_of Hash, result, log_on_failure('Should return result of type Hash')
        result.assert_valid_keys(:successes, :errors, :load_sqls)

        result[:errors].each do |e|
          puts "Trigger #{e[:trigger_name]} #{e[:exception_class]}: #{e[:exception_message]}"
        end

        created_trigger_names = result[:successes].select{|x| x[:sql]['CREATE']}.map{|x| x[:trigger_name]}
        assert_equal 2, created_trigger_names.select{|x| x['_I']}.length, log_on_failure("Should have created x insert trigger")
        assert_equal 2, created_trigger_names.select{|x| x['_U']}.length, log_on_failure("Should have created x update trigger")
        assert_equal 2, created_trigger_names.select{|x| x['_D']}.length, log_on_failure("Should have created x delete trigger")

        assert_not_nil result[:successes][0][:table_id],           log_on_failure(':table_id in successes result should be set for trigger')
        assert_not_nil result[:successes][0][:table_name],         log_on_failure(':table_name in successes result should be set for trigger')
        assert_not_nil result[:successes][0][:trigger_name],       log_on_failure(':trigger_name in successes result should be set for trigger')
        assert_not_nil result[:successes][0][:sql],                log_on_failure(':sql in successes result should be set for trigger')


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
        assert_equal 0, result[:errors].count, log_on_failure('Should not return errors from trigger generation')

        assert_not_nil Schema.find(victim_schema.id).last_trigger_deployment, log_on_failure('Timestamp of last successful trigger generation should be set')

        # second run of trigger generation should not touch the already existing triggers
        result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)
        assert_equal 0, result[:successes].length,  log_on_failure('2nd run should not touch the existing triggers')
        assert_equal 0, result[:errors].length,     log_on_failure('2nd run should not have errors')

        fixture_event_logs     = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
        event_logs_to_create = 20
        expected_event_logs = event_logs_to_create + fixture_event_logs           # created Event_Logs-records by trigger + existing from fixture

        create_event_logs_for_test(event_logs_to_create)

        real_event_logs     = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
        assert_equal expected_event_logs, real_event_logs, log_on_failure('Previous operation should create x records in Event_Logs')

        assert EventLog.last!.transaction_id.nil? ^ (key[:yn_record_txid] == 'Y'), log_on_failure("Transaction-ID must be filled only if requested! yn_record_txid=#{key[:yn_record_txid]}")

        # Dump Event_Logs and check JSON structure
        Rails.logger.info('DbTriggerTest.generate_triggers'){ "======== Dump all event_logs =========" }
        Database.select_all("SELECT * FROM Event_Logs").each do |e|
          Rails.logger.info('DbTriggerTest.generate_triggers'){ e }
          JSON.parse("{ #{e['payload']} }")                                       # Check in generated JSON is valid
        end
      end
    end
  end

  test "drop existing MOVEX CDC trigger without table config" do
    run_with_current_user do
      Table.find(victim1_table.id).update!(yn_hidden: 'Y')                      # Ensure this table is not considered for trigger generation
      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)
      assert_equal 2, result[:successes].select{|s| s[:table_id] == victim1_table.id }.length,
                   log_on_failure('drop trigger should return only drop of existing triggers for victim1')
      assert_equal 0, result[:errors].length,     log_on_failure('drop trigger should not have errors')
      assert_equal 0, result[:load_sqls].length,  log_on_failure('drop trigger should not have load SQLs')

      Table.find(victim1_table.id).update!(yn_hidden: 'N')                      # restore original state
    end
  end

  test "generate trigger for not existing table or column" do
    run_with_current_user do
      table = Table.new(schema_id: victim_schema.id, name: 'Dummy', info: 'Not existing table')
      table.save!
      column = Column.new(table_id: table.id, name: 'Dummy', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y')
      column.save!

      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)
      assert_equal 1, result[:errors].length,     log_on_failure('Not existing column should lead to error for this table')

      column.delete                                                               # Remove temporary object
      table.delete                                                                # Remove temporary object
    end
  end

  test "generate trigger with remaining trigger for not configured table" do
    begin
      Database.execute "DROP TABLE NOT_CONFIGURED"
    rescue                                                                      # Ignore drop errors
    end

    Database.execute "CREATE TABLE NOT_CONFIGURED (ID INTEGER)"
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      Database.execute "CREATE TRIGGER #{DbTriggerGeneratorBase::TRIGGER_NAME_PREFIX}_NOT_CONFIGURED FOR UPDATE ON NOT_CONFIGURED
        COMPOUND TRIGGER
          BEFORE STATEMENT IS
          BEGIN
            NULL;
          END BEFORE STATEMENT;
        END;
      "
    when 'SQLITE' then
      Database.execute "CREATE TRIGGER #{DbTriggerGeneratorBase::TRIGGER_NAME_PREFIX}_NOT_CONFIGURED UPDATE ON NOT_CONFIGURED
      BEGIN
        DELETE FROM Event_Logs WHERE 1=2;
      END;
      "
    end

    begin
      DbTrigger.generate_schema_triggers(schema_id: user_schema.id)
      assert(false, 'DbTrigger.generate_schema_triggers should raise an exception due to orphaned triggers')
    rescue Exception => e
      assert(e.message['1 orphaned trigger(s) found for schema'], 'Exception due to orphaned triggers should be raised')
    end

    Database.execute "DROP TABLE NOT_CONFIGURED"
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
      run_with_current_user do
        [victim1_table, victim2_table].each do |table|
          current_table = Table.find(table.id)                                  # load fresh state from DB
          unless current_table.update(kafka_key_handling: key[:kafka_key_handling],
                                      fixed_message_key:  key[:fixed_message_key],
                                      yn_record_txid:     key[:yn_record_txid],
                                      lock_version:       current_table.lock_version
          )
            raise table.errors.full_messages
          end
        end
      end

      existing_triggers_before = DbTrigger.find_all_by_schema_id(victim_schema.id)

      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id, dry_run: true)

      existing_triggers_after = DbTrigger.find_all_by_schema_id(victim_schema.id)

      assert_equal existing_triggers_before.count, existing_triggers_after.count, log_on_failure('existing triggers should not be touched by dry run')

      assert_instance_of Hash, result, log_on_failure('Should return result of type Hash')
      result.assert_valid_keys(:successes, :errors, :load_sqls)
    end
  end


  test "generate erroneous trigger" do
    run_with_current_user do
      condition = Condition.where(table_id: victim1_table.id, operation: 'I').first
      original_filter = condition.filter
      condition.update!(filter: "NOT EXECUTABLE SQL")                           # Set a condition that causes compile error for trigger
      result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)
      assert_equal 1, result[:errors].count, log_on_failure('Should result in compile error for one trigger')
      assert_not_nil result[:errors][0][:table_id],           log_on_failure(':table_id in error result should be set for trigger')
      assert_not_nil result[:errors][0][:table_name],         log_on_failure(':table_name in error result should be set for trigger')
      assert_not_nil result[:errors][0][:trigger_name],       log_on_failure(':trigger_name in error result should be set for trigger')
      assert_not_nil result[:errors][0][:exception_class],    log_on_failure(':exception_class in error result should be set for trigger')
      assert_not_nil result[:errors][0][:exception_message],  log_on_failure(':exception_message in error result should be set for trigger')
      assert_not_nil result[:errors][0][:sql],                log_on_failure(':sql in error result should be set for trigger')

      Rails.logger.debug('DbTriggerTest.generate erroneous trigger'){ "Reset condition to '#{original_filter}'" }
      condition.update!(filter: original_filter)                                  # reset valid entry
      DbTrigger.generate_schema_triggers(schema_id: victim_schema.id) # Create trigger again to raise DDL that commits the update on condition
    end
  end

  test "generate trigger with initialization" do
    run_with_current_user do
      org_table_attributes = victim1_table.attributes
      create_event_logs_for_test(20)                                              # create some records in victim1 before yn_initialization is set
      victim_record_count = Database.select_one "SELECT COUNT(*) FROM #{victim_schema_prefix}#{victim1_table.name}" # requires select-Grant
      max_victim_id = Database.select_one "SELECT MAX(ID) FROM #{victim_schema_prefix}#{victim1_table.name}"
      second_max_victim_id = Database.select_one "SELECT MAX(ID) FROM #{victim_schema_prefix}#{victim1_table.name} WHERE ID != :max_id", max_id: max_victim_id
      insert_condition = case MovexCdc::Application.config.db_type
                         when 'ORACLE' then ":new.ID != #{second_max_victim_id}"
                         when 'SQLITE' then "new.ID != #{second_max_victim_id}"
                         end
      sleep(4)                                                                    # avoid ORA-01466
      msgkeys = Table::VALID_KAFKA_KEY_HANDLINGS.clone(freeze: false)

      [nil, "ID != #{max_victim_id}"].each do |init_filter|
        [nil, insert_condition].each do |condition_filter|  # condition filter should be valid for execution inside trigger
          Rails.logger.debug('DbTriggerTest.generate trigger with initialization'){ "Run test for init_filer='#{init_filter}' and condition_filter='#{condition_filter}'" }

          raise "Other test process necessary because there are more key types than test loops" if msgkeys.count == 0
          kafka_key_handling = msgkeys.delete_at(0)                               # Remove used key handling so next test loop will use the next one for test
          fixed_message_key  = kafka_key_handling == 'F' ? 'Hugo' : nil
          yn_record_txid     = kafka_key_handling == 'T' ? 'Y'    : 'N'
          # update yn_init.. forces COMMIT and SELECT AS OF SCN before. This may clash with ActiveRecord SavePoint sometimes
          # see also for ORA-01466 https://stackoverflow.com/questions/34047160/table-definition-changed-despite-restore-point-creation-after-table-create-alt

          current_victim1_table = Table.find(victim1_table.id)                    # load fresh state from DB
          current_victim1_table.update!(yn_initialization:      'Y',
                                        initialization_filter:  init_filter,
                                        kafka_key_handling:     kafka_key_handling,
                                        fixed_message_key:      fixed_message_key,
                                        yn_record_txid:         yn_record_txid,
                                        lock_version:           current_victim1_table.lock_version
          ) # set a init filter for one record

          condition         = Condition.where(table_id: victim1_table.id, operation: 'I').first
          original_condition_filter = condition.filter
          if condition_filter.nil?
            condition.destroy!
          else
            condition.update! filter: condition_filter
          end

          filtered_records_count = 0
          filtered_records_count += 1 unless init_filter.nil?
          filtered_records_count += 1 unless condition_filter.nil?
          event_logs_count_before = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
          result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)
          if result[:errors].length > 0
            result[:errors].each {|e| puts e}
            assert_equal 0, result[:errors].length, log_on_failure('No errors should occur')
          end
          assert_equal 1, result[:load_sqls].length, log_on_failure('load SQLs should be generated')

          # Wait for successful initialization

          loop_count = 0
          table_init = TableInitialization.get_instance
          while (table_init.running_threads_count > 0 || table_init.init_requests_count > 0) && loop_count < 20 do
            loop_count += 1
            Rails.logger.debug('DbTriggerTest.generate trigger with initialization') { "Waiting for running_threads_count to be 0"}
            sleep 1
          end
          assert_equal 0, table_init.init_requests_count, log_on_failure('There should not be unprocessed requests')
          assert_equal 0, table_init.running_threads_count, log_on_failure('There should not be running threads')


          event_logs_count_after = Database.select_one "SELECT COUNT(*) FROM Event_Logs"
          assert_equal(victim_record_count - filtered_records_count, event_logs_count_after - event_logs_count_before,
                       log_on_failure('Each record in Victim1 should have caused an additional init record in Event_Logs except x filtered records'))

          if condition_filter.nil?
            Condition.new(condition.attributes).save!                             # recreate the dropped condition
          else
            condition.update!(filter: original_condition_filter)                  # restore original
          end
        end
      end

      restored_table = Table.find(victim1_table.id)
      restored_table.update!(org_table_attributes.select{|key, value| key != 'lock_version'}.merge(lock_version: restored_table.lock_version))  # restore original state
    end
  end

  test "generate trigger with subselect in condition" do
    run_with_current_user do
      [[200, 0], [2, 5]].each do |elem|
        compared_table_count = elem[0]
        expected_event_logs  = elem[1]

        condition         = Condition.where(table_id: victim1_table.id, operation: 'I').first
        original_condition_filter = condition.filter
        condition.update!(filter: "#{compared_table_count} < (SELECT COUNT(*) FROM Tables)") # condition should failor not

        result = DbTrigger.generate_schema_triggers(schema_id: victim_schema.id)
        assert_equal 0, result[:errors].length,     log_on_failure('drop trigger should not have errors')

        event_logs_count = Database.select_one "SELECT COUNT(*) records FROM Event_Logs"
        victim_max_id = Database.select_one "SELECT MAX(ID) max_id FROM #{victim_schema_prefix}VICTIM1"
        victim_max_id = 0 if victim_max_id.nil?
        insert_victim1_records(number_of_records_to_insert: 5, last_max_id: victim_max_id,    num_val: 1,         log_count: true)
        assert_equal(event_logs_count+expected_event_logs, Database.select_one("SELECT COUNT(*) records FROM Event_Logs"), 'Condition with subselect should prevent from creating Event_Logs')

        Condition.find(condition.id).update!(filter: original_condition_filter)     # restore original
      end
    end
  end
end
