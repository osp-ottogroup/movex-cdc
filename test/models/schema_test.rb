require 'test_helper'

class SchemaTest < ActiveSupport::TestCase
  test "create schema" do
    Schema.new(name: 'Schema1').save!
    Schema.new(name: 'Schema2', topic: 'TOPIC').save!

    assert_raise(Exception, 'Duplicate should raise unique index violation') { Schema.new(name: 'Schema1').save! }
  end

  test "select schema" do
    schemas = Schema.all
    assert(schemas.count > 0, 'Should return at least one schema')
  end

  test "update schmema without topic" do
    schema = schemas(:one)
    # Remove topics from tables of schema
    schema.tables.each do |table|
      table.topic = nil
      table.update topic:nil
    end
    success = schema.update(topic:nil)
    assert success == false, 'Validation should suppress empty schema.topic if any table of schema has no topic'
  end


end
