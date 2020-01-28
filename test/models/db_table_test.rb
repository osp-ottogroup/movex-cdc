require 'test_helper'

class DbTableTest < ActiveSupport::TestCase

  test "get db table" do
    db_tables = DbTable.all_by_schema(schemas(:one).name)
    assert(db_tables.count > 0, 'Should get at least one table of schema')
  end

end
