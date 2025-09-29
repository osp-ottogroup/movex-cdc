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

  test "duplicate column_expression" do
    assert_nothing_raised do
      existing = ColumnExpression.where(table_id: victim1_table.id, operation: 'I').first
      assert_not_nil(existing, log_on_failure('Should find existing column_expression for duplicate test'))
      duplicate = ColumnExpression.new(table_id: existing.table_id, operation: existing.operation, sql: existing.sql)
      run_with_current_user { assert_not(duplicate.valid?, 'Duplicate column_expression should not be valid') }
      assert(duplicate.errors[:base].any? { |e| e.include?('Duplicate entry found') }, log_on_failure('Should have duplicate error message'))
    end
  end
end
