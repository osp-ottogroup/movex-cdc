require 'test_helper'

class ConditionTest < ActiveSupport::TestCase
  test "create condition" do
    condition = Condition.new(table_id: tables_table.id, operation: 'U', filter: 'ID IS NOT NULL')
    run_with_current_user { condition.save! }

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Condition.new(table_id: tables_table.id, operation: 'U', filter: 'ID IS NOT NULL').save! }

    run_with_current_user { condition.destroy! }
  end

  test "select condition" do
    tables = Condition.where(table_id: tables_table.id)
    assert tables.count > 0, log_on_failure('Should return at least one condition of table')
  end
end
