require 'test_helper'

class TableTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "create table" do
    schema_without_topic = Schema.where(name: 'WITHOUT_TOPIC').first
    t1 = Table.new(schema_id: user_schema.id, name: 'Table_new',  info: 'info')
    t1.save!
    t2 = Table.new(schema_id: user_schema.id, name: 'Table_new2', info: 'info', topic: KafkaHelper.existing_topic_for_test)
    t2.save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Table.new(schema_id: user_schema.id, name: 'Table_new', info: 'info').save! }
    assert_raise(Exception, 'No topic at table and schema should raise validation error') { Table.new(schema_id: schema_without_topic.id, name: 'Without_Topic', info: 'info').save! }
    t1.destroy!
    t2.destroy!
  end

  test "select table" do
    tables = Table.where(schema_id: victim_schema.id)
    assert(tables.count > 0, 'Should return at least one table of schema')
  end

  # Check if non existing tables are also part of result
  test "all_allowed_tables_for_schema" do
    non_existing_table = Table.new(schema_id: user_schema.id, name: 'NON_EXISTING')
    non_existing_table.save!
    tables = Table.all_allowed_tables_for_schema(user_schema.id, Trixx::Application.config.db_user)
    assert(tables.count >= 3, 'Should return at least 3 tables of schema 1')
    assert(tables.select{ |t| t.name == 'TABLES'}.count > 0, 'Result should contain physically existing table with name = TABLES')
    assert(tables.select{ |t| t.name == 'COLUMNS'}.count > 0, 'Result should contain physically existing table with name=TABLES')
    assert(tables.select{ |t| t.name == 'NON_EXISTING'}.count > 0, 'Result should contain non existing table with name=NON_EXISTING')

    db_tables = DbTable.all_by_schema(user_schema.name, Trixx::Application.config.db_user)
    assert(db_tables.select{ |t| t['name'].upcase == non_existing_table.name.upcase}.count == 0, 'Table with name=NON_EXISTING should not exist physically for this test')
    non_existing_table.destroy!
  end

  test "table validations" do
    result = tables_table.update(kafka_key_handling: 'N', fixed_message_key: 'hugo')
    assert(!result, 'Validation should raise error for fixed_message_key if not empty')

    result = tables_table.update(kafka_key_handling: 'F', fixed_message_key: nil)
    assert(!result, 'Validation should raise error for fixed_message_key if empty')

    result = tables_table.update(kafka_key_handling: 'T', yn_record_txid: 'N')
    assert(!result, 'Validation should raise error for kafka_key_handling = T and yn_record_txid = N')

    result = tables_table.update(kafka_key_handling: 'X')
    assert(!result, 'Validation should raise error for wrong kafka_key_handling')

    org_topic = Schema.find(tables_table.schema_id).topic
    schema = Schema.find(user_schema.id)
    schema.tables.each {|t| t.update!(topic: KafkaHelper.existing_topic_for_test) if t.topic.nil?}  # Topic may have been changed by previous tests
    schema.update!(topic: nil)
    result = tables_table.update(topic: nil)
    assert(!result, 'Validation should raise error if neither table nor schema have valid topic')

    result = tables_table.update(yn_record_txid: 'f')
    assert(!result, 'Validation should raise error if YN-column does not contain Y or N')

    result = tables_table.update(yn_initialization: 'f')
    assert(!result, 'Validation should raise error if YN-column does not contain Y or N')

    non_existing_table = Table.new(schema_id: victim_schema.id, name: 'NON_EXISTING', topic: 'Hugo')
    non_existing_table.save!

    result = non_existing_table.update(yn_initialization: 'Y')
    assert(!result, 'Validation should raise error if yn_initialization=Y for not readable table')

    non_existing_table.destroy!
    Schema.find(tables_table.schema_id).update!(topic: org_topic)                      # restore original state
  end

  test "oldest trigger change dates per operation" do
    oldest_change_dates = Table.find(victim1_table.id).youngest_trigger_change_dates_per_operation
    ['I', 'U', 'D'].each do |operation|
      oldest_change_date = oldest_change_dates[operation]
      if ['I', 'U'].include?(operation) && ['ORACLE'].include?(Trixx::Application.config.db_type)
        assert_not_nil(oldest_change_date, 'oldest change date should be known for existing insert trigger')
      else
        assert_nil(oldest_change_date, "no trigger should exists for operation '#{operation}' or no change date available for DB")
      end
    end
  end

  test "check_table_allowed_for_db_user" do
    # Check if own table is maintainable (no exception)
    assert_nothing_raised do
      Table.check_table_allowed_for_db_user(current_user: peter_user,
                                      schema_name: Trixx::Application.config.db_victim_user,
                                      table_name:  'VICTIM1',
                                      allow_for_nonexisting_table: false
      )
    end

    assert_raise('Non-existing table should raise exception if allow_for_nonexisting_table=false') do
      Table.check_table_allowed_for_db_user(current_user:                 peter_user,
                                            schema_name:                  Trixx::Application.config.db_victim_user,
                                            table_name:                   'Non_Existing',
                                            allow_for_nonexisting_table:  false
      )
    end

    # Non-existing table should not raise exception if allow_for_nonexisting_table=true
    assert_nothing_raised do
      Table.check_table_allowed_for_db_user(current_user:                 peter_user,
                                            schema_name:                  Trixx::Application.config.db_victim_user,
                                            table_name:                   'Non_Existing',
                                            allow_for_nonexisting_table:  true
      )
    end

    case Trixx::Application.config.db_type
    when 'ORACLE' then
      assert_raise('Non-selectable table should raise exception') do
        Table.check_table_allowed_for_db_user(current_user:                 peter_user,
                                              schema_name:                  Trixx::Application.config.db_user,
                                              table_name:                   'TABLES',
                                              allow_for_nonexisting_table:  false
        )
      end

      # selectable table of other schema schould not raise exception
      assert_nothing_raised do
        Table.check_table_allowed_for_db_user(current_user:                 peter_user,
                                              schema_name:                  Trixx::Application.config.db_victim_user,
                                              table_name:                   'VICTIM1',
                                              allow_for_nonexisting_table:  false
        )
      end

      # TODO: Test for user with SELECT ANY TABLE and implicite table grants for users's roles still missing
    end
  end
end
