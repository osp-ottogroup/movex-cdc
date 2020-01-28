require 'test_helper'

class ColumnTest < ActiveSupport::TestCase
  test "create column" do
    Column.new(table_id: 1, name: 'Column_new', info: 'info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') do
      Column.new(table_id: 1, name: 'Column_new', info: 'info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
      end
  end

  test "select column" do
    columns = Column.where(table_id: 1)
    assert(columns.count > 0, 'Should return at least one column of table')
  end

  test "count active columns" do
    assert_equal(Column.count_active(table_id: 1),                     1, 'Should return the number of active columns of table')
    assert_equal(Column.count_active(table_id: 1, yn_log_update: 'Y'), 1, 'Should return the number of active columns of table for update')
    assert_equal(Column.count_active(table_id: 1, yn_log_delete: 'Y'), 0, 'Should return the number of active columns of table for update')
  end

end
