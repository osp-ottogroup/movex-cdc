require 'test_helper'

class ColumnTest < ActiveSupport::TestCase

  test "create column" do
    new_col = Column.new(table_id: tables_table.id, name: 'Column_new', info: 'info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y')
    new_col.save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') do
      Column.new(table_id: tables_table.id, name: 'Column_new', info: 'info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save!
    end
    new_col.destroy!                                                            # restore original state
  end

  test "select column" do
    columns = Column.where(table_id: tables_table.id)
    assert(columns.count > 0, 'Should return at least one column of table')
  end

  test "count active columns" do
    num_active_4        = Database.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = #{victim1_table.id} AND (YN_Log_Insert = 'Y' OR YN_Log_Update = 'Y' OR YN_Log_Delete = 'Y')"
    num_active_4_update = Database.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = #{victim1_table.id} AND (YN_Log_Update = 'Y')"
    num_active_1_delete = Database.select_one "SELECT COUNT(*) FROM Columns WHERE Table_ID = #{tables_table.id} AND (YN_Log_Delete = 'Y')"

    assert_equal(num_active_4,        Column.count_active(table_id: victim1_table.id),                     'Should return the number of active columns of table')
    assert_equal(num_active_4_update, Column.count_active(table_id: victim1_table.id, yn_log_update: 'Y'), 'Should return the number of active columns of table for update')
    assert_equal(num_active_1_delete, Column.count_active(table_id: tables_table.id, yn_log_delete: 'Y'), 'Should return the number of active columns of table for delete')
  end

  test "tag operation for all columns" do
    # Create victim tables and triggers
    create_victim_structures

    org_column_count = victim1_table.columns.count
    ['I', 'U', 'D'].each do |operation|
      ['N', 'Y'].each do |tag|                                                  # Leave all columns with tag='Y' for following tests
        column_name = Column.affected_colname_by_operation(operation).to_sym    # Column name that should be updated

        Column.tag_operation_for_all_columns(victim1_table.id, operation, tag)
        assert_equal(org_column_count, Column.where(table_id: victim1_table.id, column_name => 'Y').count, "All columns should be set with 'Y' for operation=#{operation}") if tag == 'Y'
        assert_equal(0, Column.where(table_id: victim1_table.id, column_name => 'Y').count, "No columns should remain with 'Y' for operation=#{operation}") if tag == 'N'

        Database.execute("DELETE FROM columns WHERE table_id = :table_id and name != 'NAME'", table_id: victim1_table.id)   # remove all columns except one (NAME)
        Column.tag_operation_for_all_columns(victim1_table.id, operation, tag)
        assert_equal(org_column_count, Column.where(table_id: victim1_table.id, column_name => 'Y').count, "All columns should be created and set with 'Y' for operation=#{operation}") if tag == 'Y'
        assert_equal(0, Column.where(table_id: victim1_table.id, column_name => 'Y').count, "No columns should remain with 'Y' for operation=#{operation}") if tag == 'N'
      end
    end

    # Restore original state
    Database.execute "UPDATE columns SET yn_log_insert='Y', yn_log_update='Y', yn_log_delete='Y' WHERE table_id = :table_id", table_id: victim1_table.id
  end

end
