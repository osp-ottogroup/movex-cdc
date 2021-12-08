require 'test_helper'

class DbTableTest < ActiveSupport::TestCase

  test "get db table" do
    db_tables = DbTable.all_by_schema(user_schema.name, MovexCdc::Application.config.db_user)
    assert(db_tables.count > 0, 'Should get at least one table of schema')
  end

=begin
  test "get remaining" do
    db_tables = DbTable.remaining_by_schema_id(1)
    assert(db_tables.count > 0, 'Should get at least one table of schema')
    assert_not(db_tables.map{|x| x['name']}.include?("TABLES"), 'Already observed table TABLES should not be in result')
  end
=end

end
