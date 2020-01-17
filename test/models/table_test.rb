require 'test_helper'

class TableTest < ActiveSupport::TestCase
  test "create table" do
    Table.new(schema_id: 1, name: 'Table_new', info: 'info').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Table.new(schema_id: 1, name: 'Table_new', info: 'info').save! }
  end

  test "select table" do
    tables = Table.where(schema_id: 1)
    assert(tables.count > 0, 'Should return at least one table of schema')
  end
end
