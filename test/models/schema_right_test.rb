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

  test 'process_user_request' do
    SchemaRight.process_user_request(users(:admin), [{ info: 'LaLa', schema: { name: 'HUGO'}}])

    schema = Schema.find_by_name('HUGO')
    assert_not_nil(schema, 'Should have created new schema record')
    schema_right = SchemaRight.find_by_user_id_and_schema_id(users(:admin).id, schema.id)
    assert_not_nil(schema_right, 'Should have created new schema_right record')

    assert_equal('LaLa', schema_right.info)
    SchemaRight.process_user_request(users(:admin), [{ info: 'HaHa', schema: { name: 'HUGO'}}])
    schema_right = SchemaRight.find_by_user_id_and_schema_id(users(:admin).id, schema.id) # reload object
    assert_equal('HaHa', schema_right.info, 'should update info')

    SchemaRight.process_user_request(users(:admin), [])
    assert_nil(SchemaRight.find_by_user_id_and_schema_id(users(:admin).id, schema.id), 'should remove schema right')

  end

end
