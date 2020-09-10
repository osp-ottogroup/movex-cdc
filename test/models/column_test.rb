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
    num_active_4        = Database.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = 4 AND (YN_Log_Insert = 'Y' OR YN_Log_Update = 'Y' OR YN_Log_Delete = 'Y')"
    num_active_4_update = Database.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = 4 AND (YN_Log_Update = 'Y')"
    num_active_1_delete = Database.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = 1 AND (YN_Log_Delete = 'Y')"

    assert_equal(num_active_4,        Column.count_active(table_id: 4),                     'Should return the number of active columns of table')
    assert_equal(num_active_4_update, Column.count_active(table_id: 4, yn_log_update: 'Y'), 'Should return the number of active columns of table for update')
    assert_equal(num_active_1_delete, Column.count_active(table_id: 1, yn_log_delete: 'Y'), 'Should return the number of active columns of table for delete')
  end

  test "tag operation for all columns" do
    # Create victim tables and triggers
    @victim_connection = create_victim_connection
    create_victim_structures(@victim_connection)

    org_column_count = tables(:victim1).columns.count
    table = tables(:victim1)
    ['I', 'U', 'D'].each do |operation|
      ['Y', 'N'].each do |tag|
        column_name = Column.affected_colname_by_operation(operation).to_sym    # Column name that should be updated

        Column.tag_operation_for_all_columns(table.id, operation, tag)
        assert_equal(org_column_count, Column.where(table_id: table.id, column_name => 'Y').count, "All columns should be set with 'Y' for operation=#{operation}") if tag == 'Y'
        assert_equal(0, Column.where(table_id: table.id, column_name => 'Y').count, "No columns should remain with 'Y' for operation=#{operation}") if tag == 'N'

        Database.execute("DELETE FROM Columns WHERE Table_ID = :table_id and name != 'NAME'", table_id: table.id)   # remove all columns except one (NAME)
        Column.tag_operation_for_all_columns(table.id, operation, tag)
        assert_equal(org_column_count, Column.where(table_id: table.id, column_name => 'Y').count, "All columns should be created and set with 'Y' for operation=#{operation}") if tag == 'Y'
        assert_equal(0, Column.where(table_id: table.id, column_name => 'Y').count, "No columns should remain with 'Y' for operation=#{operation}") if tag == 'N'
      end
    end

    # Remove victim structures
    drop_victim_structures(@victim_connection)
    logoff_victim_connection(@victim_connection)

  end

end
