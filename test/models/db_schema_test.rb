require 'test_helper'

class DbSchemaTest < ActiveSupport::TestCase

  test "get db schema" do
    db_schemas = DbSchema.all
    assert(db_schemas.count > 0, 'There must be at least one schema in database')
  end

  test "get remaining_schemas" do
    db_schemas = DbSchema.remaining_schemas('quark')                            # non existing user name
    match_schemas = db_schemas.to_a.map{|s| s['name'].downcase}
    assert(match_schemas.include?(Trixx::Application.config.trixx_db_user.downcase),         'DB_USER should be included in list')

    match_schemas.each {|m| puts "Match-Schema: #{m}"}
    #assert(match_schemas.include?(Trixx::Application.config.trixx_db_victim_user.downcase),  'DB_VICTIM_USER Should be included in list')

    db_schemas = DbSchema.remaining_schemas('Peter.Ramm@ottogroup.com')         # existing user name
    match_schemas = db_schemas.to_a.map{|s| s['name'].downcase}
    assert(!match_schemas.include?(Trixx::Application.config.trixx_db_user.downcase),         'Corresponding schema_right from user should not be in list')

  end

end
