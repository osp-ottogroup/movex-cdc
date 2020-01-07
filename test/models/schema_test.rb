require 'test_helper'

class SchemaTest < ActiveSupport::TestCase
  test "create schema" do
    Schema.new(name: 'Schema1').save

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Schema.new(name: 'Schema1').save }
  end
end
