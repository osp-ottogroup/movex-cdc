require 'test_helper'

class ImportExportConfigTest < ActiveSupport::TestCase

  # get the relevant column names for export
  def extract_column_names(ar_class)
    # extract column names without id, *_id, timestamps and lock_version
    ar_class.columns.select{|c| !['id', 'created_at', 'updated_at', 'lock_version'].include?(c.name) && !c.name.match?(/_id$/)}.map{|c| c.name}
  end

  def compare_hash_with_ar_record(export_hash, ar_record)
    assert(!export_hash.nil?, "#{ar_record.class} (#{ar_record}) should exist in result" )
    extract_column_names(ar_record.class).each do |col|
      assert(export_hash[col] == ar_record.send(col),
             "Column content should be the same in export for #{ar_record.class}.#{col}: '#{export_hash[col]}' is != '#{ar_record.send(col)}'"
      )
    end
  end

  # physically delete a table
  def destroy_table_with_dependencies(table)
    table.columns.each{|c| c.destroy!}
    table.conditions.each{|c| c.destroy!}
    table.destroy!
  end

  test "export_users" do
    new_user = User.new(                                                        # ensure at least two users exist
      email: 'New_user@test.com',
      db_user: MovexCdc::Application.config.db_victim_user,
      first_name: 'New',
      last_name: 'User'
    )
    new_user.save!
    exported_data = ImportExportConfig.new.export

    # check if all existing users are part of export
    User.all.each do |user|
      compare_hash_with_ar_record(exported_data['users']&.find{|e| e['email'] == user.email}, user)
    end

    new_user.destroy!                                                           # remove fake user
  end

  test "import_users" do
    exported_data = ImportExportConfig.new.export
    exported_data['users'] << {
      'email'       => 'New_user@test.com',
      'db_user'     => MovexCdc::Application.config.db_victim_user,
      'first_name'  => 'New',
      'last_name'   => 'User'
    }
    ImportExportConfig.new.import_users(exported_data)
    new_user = User.where(email: 'New_user@test.com').first
    assert(!new_user.nil?, 'New user should exist now' )

    # Check for update of attribute
    exported_data['users'].last['last_name'] = 'CHANGED'
    ImportExportConfig.new.import_users(exported_data)
    new_user = User.where(email: 'New_user@test.com').first
    assert_equal('CHANGED', new_user.last_name, 'Last name should have changed')

    new_user.destroy!                                                           # remove fake user from DB
  end

  test "export all" do
    exported_data = ImportExportConfig.new.export

    # check if all existing schemas are part of export
    Schema.all.each do |schema|
      exported_schema = exported_data['schemas']&.find{|e| e['name'] == schema.name}
      compare_hash_with_ar_record(exported_schema, schema)
      schema.tables.all do |table|
        exported_table = exported_schema['tables']&.find{|e| e['name'] == table.name}
        compare_hash_with_ar_record(exported_table, table)
        table.columns.each do |column|
          compare_hash_with_ar_record(exported_table['columns']&.find{|e| e['name'] == column.name}, column)
        end
        table.conditions.each do |condition|
          compare_hash_with_ar_record(exported_table['conditions']&.find{|e| e['operation'] == condition.operation}, condition)
        end
      end
      schema.schema_rights.each do |schema_right|
        compare_hash_with_ar_record(exported_schema['schema_rights']&.find{|e| e['email'] == schema_right.user.email}, schema_right)
      end
    end
  end

  test 'export single schema' do
    exported_data = ImportExportConfig.new.export(single_schema_name: MovexCdc::Application.config.db_user)
  end

  # a schema not in whole import list should be deactivated but not dropped
  test 'import schemas deactivate schema' do
    exported_data = ImportExportConfig.new.export
    unused_schema = Schema.new(name: 'UNUSED', topic: 'unused')
    unused_schema.save!
    unused_schema.tables          << Table.new(name: 'UNUSED_TABLE' )
    unused_schema.schema_rights   << SchemaRight.new(user_id: User.where(email: 'admin')&.first&.id)
    unused_schema.save!
    ImportExportConfig.new.import_schemas(exported_data)
    assert_equal('Y', Schema.find(unused_schema.id).tables[0].yn_hidden, 'Table should be hidden now')
    assert_equal(0, Schema.find(unused_schema.id).schema_rights.count, 'SchemaRights should be deleted')
  end

  test 'import new schema' do
    exported_data = ImportExportConfig.new.export
    exported_data['schemas'] << {
      'name'          => 'NEW_SCHEMA',
      'topic'         => 'new_topic',
      'wrong_colname' => 'no more existent column name',                        # This should test for toleration of columns not existing in DB
      'tables'        => [{
                            'name'          => 'NEW_TABLE',
                            'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                            'columns'       => [{
                                                  'name' => 'NEW_COL',
                                                  'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                                                }],
                            'conditions'    => [{
                                                  'operation' => 'I',
                                                  'filter'    => '1 = 2',
                                                  'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                                                }]
                          }],
      'schema_rights' => [{
                            'email'         => 'admin',
                            'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                          }]
    }
    ImportExportConfig.new.import_schemas(exported_data)
    new_schema = Schema.where(name: 'NEW_SCHEMA').first
    assert_not_equal(nil, new_schema, 'The new schema should be created')
    assert_equal('NEW_SCHEMA',  new_schema.name,                                'The new schema should be created with this name')
    assert_equal('NEW_TABLE',   new_schema.tables[0].name,                      'A new table should be created with this name')
    assert_equal('NEW_COL',     new_schema.tables[0].columns[0].name,           'A new column should be created with this name')
    assert_equal('I',           new_schema.tables[0].conditions[0].operation,   'A new condition should be created with this operation')
    assert_equal('admin',       new_schema.schema_rights[0].user.email,         'A new schema_right should be created with this user')

    # Remove aditional test schema
    new_schema.tables.each{|t| destroy_table_with_dependencies(t) }
    new_schema.schema_rights.each{|sr| sr.destroy!}
    new_schema.destroy!
  end

  # test import of all schemas from JSON with missing old and added new: tables, columns, conditions, schema_rights
  test 'import existing schemas' do
    test_table = Table.new(schema_id: Schema.first.id, name: 'TEST_TABLE_IMPORT')
    test_table.save!
    test_table.columns    << Column.new(name: 'TEST_TABLE_COL1')
    test_table.columns    << Column.new(name: 'TEST_TABLE_COL2')
    test_table.conditions << Condition.new(operation: 'I', filter: '2 = 3')
    test_table.conditions << Condition.new(operation: 'U', filter: '3 = 4')
    test_table.save!

    test_user_i = User.new(email: 'test_user_i', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Test', last_name: 'I' ); test_user_i.save!
    test_user_u = User.new(email: 'test_user_u', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Test', last_name: 'U' ); test_user_u.save!
    test_user_d = User.new(email: 'test_user_d', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Test', last_name: 'D' ); test_user_d.save!

    SchemaRight.new(schema_id: Schema.first.id, user_id: test_user_u.id).save!  # SchemaRight existing in DB and import

    exported_data = ImportExportConfig.new.export                               # get JSON data to test for import
    old_topic = exported_data['schemas'][0]['topic']
    exported_data['schemas'][0]['topic'] = 'Changed topic'

    # Table that exists in DB but is not existing in import data
    first_schema = Schema.where(name: exported_data['schemas'][0]['name']).first
    missing_table = Table.new(schema_id: first_schema.id, name: 'MISSING TABLE')
    missing_table.save!

    # Table that is not existing in DB but in import data
    exported_data['schemas'][0]['tables'] << {
      'name'        => 'ADDED_TABLE',
      'columns'     => [{ 'name' => 'COL1'}, { 'name' => 'COL2'}],
      'conditions'  => [{ 'operation' => 'I', 'filter' => '1 = 2'}],
    }

    # existing table with added and deleted and changed column and conditions
    test_table_hash = exported_data['schemas'][0]['tables'].find{|t| t['name'] == 'TEST_TABLE_IMPORT'}
    raise "Hash value for table 'TEST_TABLE_IMPORT' not found in export" if test_table_hash.nil?
    test_table_hash['columns'] << { 'name' => 'TEST_TABLE_COL3'}
    test_table_hash['columns'].find{|c| c['name'] == 'TEST_TABLE_COL2'}['yn_log_update'] = 'Y'
    test_table_hash['columns'].delete_if{|c| c['name'] == 'TEST_TABLE_COL1'}
    test_table_hash['conditions'] << { 'operation' => 'D', 'filter' => '5 = 6'}
    test_table_hash['conditions'].find{|c| c['operation'] == 'U'}['filter'] = 'changed'
    test_table_hash['conditions'].delete_if{|c| c['operation'] == 'I'}

    SchemaRight.new(schema_id: Schema.first.id, user_id: test_user_i.id).save!  # SchemaRight existing in DB but not in import
    exported_data['schemas'][0]['schema_rights'] << { 'email' => test_user_d.email}     # SchemaRight not existing in DB but in import
    exported_data['schemas'][0]['schema_rights'].find{|sr| sr['email'] == test_user_u.email}['yn_deployment_granted'] = 'Y'

    ImportExportConfig.new.import_schemas(exported_data)                        # Now import the data for test
    assert_equal('Changed topic', Schema.where(name: exported_data['schemas'][0]['name']).first.topic, 'Changed topic should occur in DB')
    assert_equal('Y', Table.find(missing_table.id).yn_hidden, 'Missing table should be set hidden after import')
    assert_equal(1, Table.where(name: 'ADDED_TABLE').count, 'Additional table from import should exist in DB now')  # ensure also that only one table exists with this name
    added_table = Table.where(name: 'ADDED_TABLE').first
    reloaded_test_table = Table.find(test_table.id)                                     # reload changes from DB
    assert_equal(test_table.name,       reloaded_test_table.name,       'Table with same ID should be the same after import')
    assert_equal(test_table.schema_id,  reloaded_test_table.schema_id,  'Table with same ID should be the same after import')
    test_table = reloaded_test_table
    assert_equal(2,       added_table.columns.count,              'Additional table from import should have columns')
    assert_equal('COL2',  added_table.columns.last.name,          'Additional table from import should have columns with name')
    assert_equal(1,       added_table.conditions.count,           'Additional table from import should have condition')
    assert_equal('I',     added_table.conditions.first.operation, 'Additional table from import should have condition with operation')
    assert_equal('1 = 2', added_table.conditions.first.filter,    'Additional table from import should have condition with filter')
    assert_equal(1,       test_table.columns.select{|c| c.name == 'TEST_TABLE_COL3'}.count,                           'Columns should be added to existing table')
    assert_equal(1,       test_table.columns.select{|c| c.name == 'TEST_TABLE_COL2' && c.yn_log_update == 'Y'}.count, 'Column should be changed in existing table')
    assert_equal(0,       test_table.columns.select{|c| c.name == 'TEST_TABLE_COL1'}.count,                           'Column should be deleted in existing table')
    assert_equal(1,       test_table.conditions.select{|c| c.operation == 'D'}.count,                                 'Condition should be added to existing table')
    assert_equal(1,       test_table.conditions.select{|c| c.operation == 'U' && c.filter == 'changed'}.count,        'Condition should be changed in existing table')
    assert_equal(0,       test_table.conditions.select{|c| c.operation == 'I'}.count,                                 'Condition should be deleted in existing table')
    assert_equal(1,       first_schema.schema_rights.select{|sr| sr.user_id == test_user_d.id}.count,                 'SchemaRight should be added to existing schema')
    assert_equal(1,       first_schema.schema_rights.select{|sr| sr.user_id == test_user_u.id && sr.yn_deployment_granted == 'Y'}.count, 'SchemaRight should be changed in existing schema')
    assert_equal(0,       first_schema.schema_rights.select{|sr| sr.user_id == test_user_i.id}.count,                 'SchemaRight should be deleted in existing schema')

    # restore original data
    SchemaRight.where(user_id: test_user_i.id).each {|sr| sr.destroy!}; test_user_i.destroy!
    SchemaRight.where(user_id: test_user_u.id).each {|sr| sr.destroy!}; test_user_u.destroy!
    SchemaRight.where(user_id: test_user_d.id).each {|sr| sr.destroy!}; test_user_d.destroy!
    destroy_table_with_dependencies(added_table)
    destroy_table_with_dependencies(Table.find(test_table.id))
    Table.find(missing_table.id).destroy!                                       # Table is only set hidden by import
    Schema.first.update!(topic: old_topic)
  end

  # only check for not touching other schemas during import
  test 'import single schema' do
    exported_data = ImportExportConfig.new.export                               # get JSON data to test for import
    schema0 = Schema.where(name: exported_data['schemas'][0]['name']).first
    org_topic = schema0.topic
    exported_data['schemas'].each {|s| s['topic'] = 'CHANGED_TOPIC'}
    ImportExportConfig.new.import_schemas(exported_data, schema_name_to_pick: schema0.name)

    Schema.all.each do |schema|
      if schema.id == schema0.id
        assert_equal('CHANGED_TOPIC', schema.topic, 'The first schema should be updated')
      else
        assert_not_equal('CHANGED_TOPIC', schema.topic, 'The other schemas should not be updated')
      end
    end

    # Restore original state
    Schema.find(schema0.id).update!(topic: org_topic)
  end

  test 'import schema with missing user' do
    exported_data = ImportExportConfig.new.export                               # get JSON data to test for import
    exported_data['schemas'][0]['schema_rights'] << { 'email'       => 'NON_EXISTING' }

    begin
      exported_users   = ImportExportConfig.new.import_schemas(exported_data)
      raise "Missing user should raise exception before executing this line"
    rescue Exception => e
      assert(e.message["doesn't exist neither in the DB"], "Missing user should raise specific exception, but is #{e.class}:#{e.message}")
    end

    exported_data['users'] << {
      'email'             => 'NON_EXISTING',
      'db_user'           => MovexCdc::Application.config.db_victim_user,
      'first_name'        => 'non',
      'last_name'         => 'exist',
      'yn_admin'          => 'Y',
      'yn_account_locked' => 'N'
    }

    ImportExportConfig.new.import_schemas(exported_data)     # Now import with valid user
    user = User.where(email: 'NON_EXISTING').first
    assert_not_nil(user, 'Missing user should be created')
    assert_equal('N', user.yn_admin, 'User should not remain admin')
    assert_equal('Y', user.yn_account_locked, 'User should not locked')

    # restore original state
    user.schema_rights.each{|sr| sr.destroy!}
    user.destroy!
  end
end
