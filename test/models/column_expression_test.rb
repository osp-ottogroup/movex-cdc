require 'test_helper'

class ColumnExpressionTest < ActiveSupport::TestCase
  test "create column_expression" do
    assert_nothing_raised do
      column_expression = ColumnExpression.new(table_id: tables_table.id, operation: 'U', sql: 'SELECT Hugo FROM DUal')
      run_with_current_user { column_expression.save! }
      run_with_current_user { column_expression.destroy! }
    end
  end

  test "select column_expression" do
    assert_nothing_raised do
      tables = ColumnExpression.where(table_id: victim1_table.id)
      assert tables.count > 0, log_on_failure('Should return at least one column_expression of table')
    end
  end
end
