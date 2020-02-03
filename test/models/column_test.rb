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
    num_active_4        = TableLess.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = 4 AND (YN_Log_Insert = 'Y' OR YN_Log_Update = 'Y' OR YN_Log_Delete = 'Y')"
    num_active_4_update = TableLess.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = 4 AND (YN_Log_Update = 'Y')"
    num_active_1_delete = TableLess.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = 1 AND (YN_Log_Delete = 'Y')"

    assert_equal(num_active_4,        Column.count_active(table_id: 4),                     'Should return the number of active columns of table')
    assert_equal(num_active_4_update, Column.count_active(table_id: 4, yn_log_update: 'Y'), 'Should return the number of active columns of table for update')
    assert_equal(num_active_1_delete, Column.count_active(table_id: 1, yn_log_delete: 'Y'), 'Should return the number of active columns of table for delete')
  end

end
