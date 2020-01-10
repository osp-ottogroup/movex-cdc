require 'test_helper'

class ColumnTest < ActiveSupport::TestCase
  test "create column" do
    Column.new(table_id: 1, name: 'Column_new', info: 'info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save

    assert_raise(Exception, 'Duplicate should raise unique index violation') do
      Column.new(table_id: 1, name: 'Column_new', info: 'info', yn_log_insert: 'Y', yn_log_update: 'Y', yn_log_delete: 'Y').save
      end
  end
end
