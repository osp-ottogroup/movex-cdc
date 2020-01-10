require 'test_helper'

class TableTest < ActiveSupport::TestCase
  test "create table" do
    Table.new(schema_id: 1, name: 'Table_new', info: 'info').save

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Table.new(schema_id: 1, name: 'Table_new', info: 'info').save }
  end
end
