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
    Table.new(schema_id: 1, name: 'Table_new2', info: 'info', topic: 'TOPIC').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Table.new(schema_id: 1, name: 'Table_new', info: 'info').save! }
    assert_raise(Exception, 'No topic at table and schema should raise validation error') { Table.new(schema_id: 3, name: 'Without_Topic', info: 'info').save! }
  end

  test "select table" do
    tables = Table.where(schema_id: 1)
    assert(tables.count > 0, 'Should return at least one table of schema')
  end

  test "table validations" do
    table = tables(:one)

    result = table.update(kafka_key_handling: 'N', fixed_message_key: 'hugo')
    assert(!result, 'Validation should raise error for fixed_message_key if not empty')

    result = table.update(kafka_key_handling: 'F', fixed_message_key: nil)
    assert(!result, 'Validation should raise error for fixed_message_key if empty')

    result = table.update(kafka_key_handling: 'X')
    assert(!result, 'Validation should raise error for wrong kafka_key_handling')

    schemas(:one).update(topic: nil)
    result = table.update(topic: nil)
    assert(!result, 'Validation should raise error if neither table nor schema have valid topic')

  end

  test "oldest trigger change dates per operation" do
    oldest_change_dates = tables(:victim1).oldest_trigger_change_dates_per_operation
    ['I', 'U', 'D'].each do |operation|
      oldest_change_date = oldest_change_dates[operation]
      if operation == 'I' && ['ORACLE'].include?(Trixx::Application.config.trixx_db_type)
        assert_not_nil(oldest_change_date, 'oldest change date should be known for existing insert trigger')
      else
        assert_nil(oldest_change_date, 'no trigger should exists for operation or no change date available for DB')
      end
    end
  end

end
