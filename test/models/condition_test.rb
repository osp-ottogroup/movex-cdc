require 'test_helper'

class ConditionTest < ActiveSupport::TestCase
  test "create condition" do
    Condition.new(table_id: 1, operation: 'U', filter: 'ID IS NOT NULL').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Condition.new(table_id: 1, operation: 'U', filter: 'ID IS NOT NULL').save! }
  end

  test "select condition" do
    tables = Condition.where(table_id: 1)
    assert(tables.count > 0, 'Should return at least one condition of table')
  end
end
