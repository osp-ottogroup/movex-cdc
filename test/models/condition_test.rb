require 'test_helper'

class ConditionTest < ActiveSupport::TestCase
  test "create condition" do
    Condition.new(table_id: tables_table.id, operation: 'U', filter: 'ID IS NOT NULL').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Condition.new(table_id: tables_table.id, operation: 'U', filter: 'ID IS NOT NULL').save! }
  end

  test "select condition" do
    tables = Condition.where(table_id: tables_table.id)
    assert(tables.count > 0, 'Should return at least one condition of table')
  end
end
