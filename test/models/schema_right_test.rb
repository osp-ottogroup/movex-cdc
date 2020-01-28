require 'test_helper'

class SchemaRightTest < ActiveSupport::TestCase
  test "create schema_right" do
    SchemaRight.new(user_id: 2, schema_id: 1, info: 'Info').save!
    assert_raise(Exception, 'Duplicate should raise unique index violation') { SchemaRight.new(user_id: 2, schema_id: 1, info: 'Info').save! } # 1/1 from fixture
  end

  test "select schema_right" do
    schema_rights = SchemaRight.all
    assert(schema_rights.count > 0, 'Should return at least one record')
  end

end
