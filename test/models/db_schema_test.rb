require 'test_helper'

class DbSchemaTest < ActiveSupport::TestCase

  test "get db schema" do
    db_schemas = DbSchema.all
    assert(db_schemas.count > 0, 'There must be at least one schema in database')
  end

  test "get remaining_schemas" do
    db_schemas = DbSchema.remaining_schemas('quark')                            # non existing user name
    assert(db_schemas.to_a.include?('name' =>'TRIXX'), 'Should be included in list')
    assert(db_schemas.to_a.include?('name' =>'TRIXX_VICTIM'), 'Should be included in list')

    db_schemas = DbSchema.remaining_schemas('Peter.Ramm@ottogroup.com')         # existing user name
    assert(db_schemas.to_a.include?('name' =>'TRIXX'), 'Should be included in list')
    assert(!(db_schemas.to_a.include? 'name' => Trixx::Application.config.trixx_db_user), 'Corresponding schema_right from user should not be in list')

  end

end
