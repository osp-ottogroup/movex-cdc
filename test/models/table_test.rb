require 'test_helper'

class TableTest < ActiveSupport::TestCase
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


  test "create table" do
    Table.new(schema_id: 1, name: 'Table_new',  info: 'info').save!
    Table.new(schema_id: 1, name: 'Table_new2', info: 'info', topic: KafkaHelper.existing_topic_for_test).save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Table.new(schema_id: 1, name: 'Table_new', info: 'info').save! }
    assert_raise(Exception, 'No topic at table and schema should raise validation error') { Table.new(schema_id: 3, name: 'Without_Topic', info: 'info').save! }
  end

  test "select table" do
    tables = Table.where(schema_id: 1)
    assert(tables.count > 0, 'Should return at least one table of schema')
  end

  # Check if non existing tables are also part of result
  test "all_allowed_tables_for_schema" do
    tables = Table.all_allowed_tables_for_schema(schemas(:one).id, Trixx::Application.config.trixx_db_user)
    assert(tables.count >= 3, 'Should return at least 3 tables of schema 1')
    assert(tables.select{ |t| t.id == 1}.count > 0, 'Result should contain physically existing table with ID=1')
    assert(tables.select{ |t| t.id == 2}.count > 0, 'Result should contain physically existing table with ID=2')
    assert(tables.select{ |t| t.id == 3}.count > 0, 'Result should contain non existing table with ID=3')

    db_tables = DbTable.all_by_schema(schemas(:one).name, Trixx::Application.config.trixx_db_user)
    assert(db_tables.select{ |t| t['name'].upcase == tables(:deletable).name.upcase}.count == 0, 'Table with ID=3 should not exist physically for this test')
  end

  test "table validations" do
    table = tables(:one)

    result = table.update(kafka_key_handling: 'N', fixed_message_key: 'hugo')
    assert(!result, 'Validation should raise error for fixed_message_key if not empty')

    result = table.update(kafka_key_handling: 'F', fixed_message_key: nil)
    assert(!result, 'Validation should raise error for fixed_message_key if empty')

    result = table.update(kafka_key_handling: 'T', yn_record_txid: 'N')
    assert(!result, 'Validation should raise error for kafka_key_handling = T and yn_record_txid = N')

    result = table.update(kafka_key_handling: 'X')
    assert(!result, 'Validation should raise error for wrong kafka_key_handling')

    schemas(:one).update(topic: nil)
    result = table.update(topic: nil)
    assert(!result, 'Validation should raise error if neither table nor schema have valid topic')

    result = table.update(yn_record_txid: 'f')
    assert(!result, 'Validation should raise error if YN-column does not contain Y or N')
  end

  test "oldest trigger change dates per operation" do
    oldest_change_dates = tables(:victim1).youngest_trigger_change_dates_per_operation
    ['I', 'U', 'D'].each do |operation|
      oldest_change_date = oldest_change_dates[operation]
      if operation == 'I' && ['ORACLE'].include?(Trixx::Application.config.trixx_db_type)
        assert_not_nil(oldest_change_date, 'oldest change date should be known for existing insert trigger')
      else
        assert_nil(oldest_change_date, 'no trigger should exists for operation or no change date available for DB')
      end
    end
  end

  test "check_table_allowed_for_db_user" do
    current_user = users(:one)
    # Check if own table is maintainable (no exception)
    assert_nothing_raised do
      Table.check_table_allowed_for_db_user(current_user: current_user,
                                      schema_name: Trixx::Application.config.trixx_db_victim_user,
                                      table_name:  tables(:victim1).name,
                                      allow_for_nonexisting_table: false
      )
    end

    assert_raise('Non-existing table should raise exception if allow_for_nonexisting_table=false') do
      Table.check_table_allowed_for_db_user(current_user:                 current_user,
                                            schema_name:                  Trixx::Application.config.trixx_db_victim_user,
                                            table_name:                   'Non_Existing',
                                            allow_for_nonexisting_table:  false
      )
    end

    # Non-existing table should not raise exception if allow_for_nonexisting_table=true
    assert_nothing_raised do
      Table.check_table_allowed_for_db_user(current_user:                 current_user,
                                            schema_name:                  Trixx::Application.config.trixx_db_victim_user,
                                            table_name:                   'Non_Existing',
                                            allow_for_nonexisting_table:  true
      )
    end

    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      assert_raise('Non-selectable table should raise exception') do
        Table.check_table_allowed_for_db_user(current_user:                 current_user,
                                              schema_name:                  Trixx::Application.config.trixx_db_user,
                                              table_name:                   'TABLES',
                                              allow_for_nonexisting_table:  false
        )
      end

      # selectable table of other schema schould not raise exception
      assert_nothing_raised do
        Table.check_table_allowed_for_db_user(current_user:                 current_user,
                                              schema_name:                  Trixx::Application.config.trixx_db_victim_user,
                                              table_name:                   tables(:victim1).name,
                                              allow_for_nonexisting_table:  false
        )
      end

      # TODO: Test for user with SELECT ANY TABLE and implicite table grants for users's roles still missing
    end
  end
end
