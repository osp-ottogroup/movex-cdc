require 'test_helper'

class DbSchemaTest < ActiveSupport::TestCase

  test "get db schema" do
    db_schemas = DbSchema.all
    assert_equal(true, db_schemas.count > 0, 'There must be at least one schema in database')
  end

end
