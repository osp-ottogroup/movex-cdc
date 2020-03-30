require 'test_helper'

class TableTest < ActiveSupport::TestCase
  test "create table" do
    Table.new(schema_id: 1, name: 'Table_new',  info: 'info').save!
    Table.new(schema_id: 1, name: 'Table_new2', info: 'info', topic: 'TOPIC').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Table.new(schema_id: 1, name: 'Table_new', info: 'info').save! }
    assert_raise(Exception, 'No topic at table and schema should raise validation error') { Table.new(schema_id: 3, name: 'Without_Topic', info: 'info').save! }
  end

  test "select table" do
    tables = Table.where(schema_id: 1)
    assert(tables.count > 0, 'Should return at least one table of schema')
  end
end
