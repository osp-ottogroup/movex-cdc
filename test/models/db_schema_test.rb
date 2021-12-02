require 'test_helper'

class DbSchemaTest < ActiveSupport::TestCase
  setup do
    # Create victim tables and triggers
    create_victim_structures
  end

  test "get db schema" do
    db_schemas = DbSchema.all
    assert(db_schemas.count > 0, 'There must be at least one schema in database')
  end

  test "get authorizable_schemas" do
    db_schemas = DbSchema.authorizable_schemas('quark', nil)                    # non existing user name
    case Trixx::Application.config.db_type
    when 'ORACLE' then
      assert_equal 0, db_schemas.count, 'Non existing email should not find any schema'
    when 'SQLITE' then
      assert_equal 1, db_schemas.count, 'Non existing email should find main'
    else
      raise "Specify test condition for db_type"
    end

    db_schemas = DbSchema.authorizable_schemas(peter_user.email, nil) # existing user name
    match_schemas = db_schemas.to_a.map{|s| s['name']}
    assert(!match_schemas.include?(peter_user.db_user), 'Corresponding schema_right from user should not be in list')

    SchemaRight.delete_all
    db_schemas = DbSchema.authorizable_schemas(peter_user.email, nil) # existing user name
    match_schemas = db_schemas.to_a.map{|s| s['name']}
    assert(match_schemas.include?(peter_user.db_user), 'users DB_User should be in list now for existing user')

    db_schemas = DbSchema.authorizable_schemas(nil, peter_user.db_user) # while creating user (not already saved)
    match_schemas = db_schemas.to_a.map{|s| s['name']}
    assert(match_schemas.include?(peter_user.db_user), 'users DB_User should be in list now for new user')

    GlobalFixtures.restore_schema_rights
  end

  test "valid_schema_name" do
    assert !DbSchema.valid_schema_name?('quark'), 'Schema quark should not exist'
    assert DbSchema.valid_schema_name?(Trixx::Application.config.db_user), 'Schema of DB_USER should not exist'
  end

end
