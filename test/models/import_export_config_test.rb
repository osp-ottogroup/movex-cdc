require 'test_helper'

class ImportExportConfigTest < ActiveSupport::TestCase

  # get the relevant column names for export
  def extract_column_names(ar_class)
    # extract column names without id, *_id, timestamps and lock_version
    ar_class.columns.select{|c| !['id', 'created_at', 'updated_at', 'lock_version', 'last_trigger_deployment'].include?(c.name) && !c.name.match?(/_id$/)}.map{|c| c.name}
  end

  # Compare a hash from export with an AR record
  # The hash must contain all relevant column names of the AR record
  # # param [Hash] export_hash Hash from export
  # # param [ActiveRecord] ar_record AR record to compare with
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
    table.column_expressions.each{|c| c.destroy!}
    table.destroy!
  end

  setup do
    # Ensure config data is loaded
    create_victim_structures
  end


  test "export_users" do
    run_with_current_user do
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
  end

  test "import_users" do
    exported_data = ImportExportConfig.new.export
    exported_data['users'] << {
      'email'       => 'New_user@test.com',
      'db_user'     => MovexCdc::Application.config.db_victim_user,
      'first_name'  => 'New',
      'last_name'   => 'User'
    }
    run_with_current_user { ImportExportConfig.new.import_users(exported_data) }
    new_user = User.where(email: 'New_user@test.com').first
    assert(!new_user.nil?, 'New user should exist now' )

    # Check for update of attribute
    exported_data['users'].last['last_name'] = 'CHANGED'
    run_with_current_user { ImportExportConfig.new.import_users(exported_data) }
    new_user = User.where(email: 'New_user@test.com').first
    assert_equal('CHANGED', new_user.last_name, 'Last name should have changed')

    run_with_current_user { new_user.destroy! }                                 # remove fake user from DB
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
        table.column_expressions.each do |ce|
          compare_hash_with_ar_record(exported_table['column_expressions']&.find{|e| e['operation'] == ce.operation && e['sql'] == ce.sql}, ce)
        end
      end
      schema.schema_rights.each do |schema_right|
        compare_hash_with_ar_record(exported_schema['schema_rights']&.find{|e| e['email'] == schema_right.user.email}, schema_right)
      end
    end
  end

  test 'export single schema' do
    assert_nothing_raised do
      exported_data = ImportExportConfig.new.export(single_schema_name: MovexCdc::Application.config.db_user)
    end
  end

  # a schema not in whole import list should be deactivated but not dropped
  test 'import schemas deactivate schema' do
    run_with_current_user do
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
  end

  test 'import new schema' do
    # Remove possibly existing test schema
    run_with_current_user do
      new_schema = Schema.find_by_name('NEW_SCHEMA')
      unless new_schema.nil?
        new_schema.tables.each{|t| destroy_table_with_dependencies(t) }
        new_schema.schema_rights.each{|sr| sr.destroy!}
        new_schema.destroy!
      end
    end

    exported_data = ImportExportConfig.new.export
    exported_data['schemas'] << {
      'name'          => 'NEW_SCHEMA',
      'topic'         => 'new_topic',
      'wrong_colname' => 'no more existent column name',                        # This should test for toleration of columns not existing in DB
      'tables'        => [{
                            'name'          => 'NEW_TABLE',
                            'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                            'columns'       => [
                              {
                                'name' => 'NEW_COL',
                                'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                              }
                            ],
                            'conditions'    => [
                              {
                                'operation' => 'I',
                                'filter'    => '1 = 2',
                                'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                              }
                            ],
                            'column_expressions' => [{
                                "operation" => "I",
                                "sql"       => "SELECT JSON_OBJECT('SYSDATE' VALUE SYSDATE) Val1 FROM DUAL"
                              },
                              {
                                "operation" => "I",
                                "sql"       => "SELECT JSON_OBJECT('DATUM' VALUE SYSDATE) Val2 FROM DUAL"
                              }
                            ]
                          }],
      'schema_rights' => [{
                            'email'         => 'admin',
                            'wrong_colname' => 'no more existent column name',  # This should test for toleration of columns not existing in DB
                          }]
    }
    run_with_current_user { ImportExportConfig.new.import_schemas(exported_data) }
    new_schema = Schema.where(name: 'NEW_SCHEMA').first
    assert_not_equal(nil, new_schema, 'The new schema should be created')
    assert_equal('NEW_SCHEMA',  new_schema.name,                       'The new schema should be created with this name')
    new_table = new_schema.tables[0]
    assert_equal('NEW_TABLE',   new_table.name,                        'A new table should be created with this name')
    assert_equal('NEW_COL',     new_table.columns[0].name,             'A new column should be created with this name')
    assert_equal('I',           new_table.conditions[0].operation,     'A new condition should be created with this operation')
    assert_equal('1 = 2',       new_table.conditions[0].filter,        'A new condition should be created with this filter')
    assert_equal('I',           new_table.column_expressions[0].operation, 'A new column_expression should be created with this operation')
    assert_equal(1,
                 new_table.column_expressions.select{|ce| ce.sql == "SELECT JSON_OBJECT('SYSDATE' VALUE SYSDATE) Val1 FROM DUAL"}.count,
                 'A new column_expression should be created with this sql'
    )
    assert_equal('admin',       new_schema.schema_rights[0].user.email,'A new schema_right should be created with this user')

    # Remove aditional test schema
    run_with_current_user do
      new_schema.tables.each{|t| destroy_table_with_dependencies(t) }
      new_schema.schema_rights.each{|sr| sr.destroy!}
      new_schema.destroy!
    end
  end

  # test import of all schemas from JSON with missing old and added new: tables, columns, conditions, schema_rights
  test 'import existing schemas' do
    run_with_current_user do
      test_schema = Schema.first                                                  # arbitrary choosen Schema for manipulation
      test_table = Table.new(schema_id: test_schema.id, name: 'TEST_TABLE_IMPORT')
      test_table.save!
      test_table.columns    << Column.new(name: 'TEST_TABLE_COL1')
      test_table.columns    << Column.new(name: 'TEST_TABLE_COL2')
      test_table.conditions << Condition.new(operation: 'I', filter: '2 = 3')
      test_table.conditions << Condition.new(operation: 'U', filter: '3 = 4')
      test_table.column_expressions << ColumnExpression.new(operation: 'I', sql: 'sql_i')
      test_table.column_expressions << ColumnExpression.new(operation: 'U', sql: 'sql_u')
      test_table.save!

      test_user_i = User.new(email: 'test_user_i', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Test', last_name: 'I' ); test_user_i.save!
      test_user_u = User.new(email: 'test_user_u', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Test', last_name: 'U' ); test_user_u.save!
      test_user_d = User.new(email: 'test_user_d', db_user: MovexCdc::Application.config.db_victim_user, first_name: 'Test', last_name: 'D' ); test_user_d.save!

      SchemaRight.new(schema_id: test_schema.id, user_id: test_user_u.id).save!  # SchemaRight existing in DB and import

      exported_data = ImportExportConfig.new.export                               # get JSON data to test for import
      test_schema_hash = exported_data['schemas'].find{|s| s['name'] == test_schema.name}
      old_topic = test_schema_hash['topic']
      test_schema_hash['topic'] = 'Changed topic'

      # Table that exists in DB but is not existing in import data
      missing_table = Table.new(schema_id: test_schema.id, name: 'MISSING TABLE')
      missing_table.save!

      # Table that is not existing in DB but in import data
      test_schema_hash['tables'] << {
        'name'                => 'ADDED_TABLE',
        'columns'             => [{ 'name' => 'COL1'}, { 'name' => 'COL2'}],
        'conditions'          => [{ 'operation' => 'I', 'filter' => '1 = 2'}],
        'column_expressions'  => [{ 'operation' => 'I', 'sql' => "SELECT '{ \"ce\": 5}'"}],
      }

      # existing table with added and deleted and changed column, conditions and column_expressions
      test_table_hash = test_schema_hash['tables'].find{|t| t['name'] == 'TEST_TABLE_IMPORT'}
      raise "Hash value for table 'TEST_TABLE_IMPORT' not found in export" if test_table_hash.nil?
      test_table_hash['columns'] << { 'name' => 'TEST_TABLE_COL3'}
      test_table_hash['columns'].find{|c| c['name'] == 'TEST_TABLE_COL2'}['yn_log_update'] = 'Y'
      test_table_hash['columns'].delete_if{|c| c['name'] == 'TEST_TABLE_COL1'}
      test_table_hash['conditions'] << { 'operation' => 'D', 'filter' => '5 = 6'}
      test_table_hash['conditions'].find{|c| c['operation'] == 'U'}['filter'] = 'changed'
      test_table_hash['conditions'].delete_if{|c| c['operation'] == 'I'}
      test_table_hash['column_expressions'] << { 'operation' => 'D', 'sql' => 'sql_d'}
      test_table_hash['column_expressions'].find{|c| c['operation'] == 'U'}['sql'] = 'sql_u_changed'
      test_table_hash['column_expressions'].delete_if{|c| c['operation'] == 'I'}

      SchemaRight.new(schema_id: test_schema.id, user_id: test_user_i.id).save! # SchemaRight existing in DB but not in import
      test_schema_hash['schema_rights'] << { 'email' => test_user_d.email}      # SchemaRight not existing in DB but in import
      test_schema_hash['schema_rights'].find{|sr| sr['email'] == test_user_u.email}['yn_deployment_granted'] = 'Y'

      ImportExportConfig.new.import_schemas(exported_data)                      # Now import the data for test
      assert_equal('Changed topic', Schema.find(test_schema.id).topic, 'Changed topic should occur in DB')
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
      assert_equal(1,       test_table.column_expressions.select{|c| c.operation == 'D'}.count,                            'Column Expression should be added to existing table')
      assert_equal(1,       test_table.column_expressions.select{|c| c.operation == 'U' && c.sql == 'sql_u_changed'}.count,'Column Expression should be changed in existing table')
      assert_equal(0,       test_table.column_expressions.select{|c| c.operation == 'I'}.count,                            'Column Expression should be deleted in existing table')
      assert_equal(1,       test_schema.schema_rights.select{|sr| sr.user_id == test_user_d.id}.count,                  'SchemaRight should be added to existing schema')
      assert_equal(1,       test_schema.schema_rights.select{|sr| sr.user_id == test_user_u.id && sr.yn_deployment_granted == 'Y'}.count, 'SchemaRight should be changed in existing schema')
      assert_equal(0,       test_schema.schema_rights.select{|sr| sr.user_id == test_user_i.id}.count,                  'SchemaRight should be deleted in existing schema')

      # restore original data
      SchemaRight.where(user_id: test_user_i.id).each {|sr| sr.destroy!}; test_user_i.destroy!
      SchemaRight.where(user_id: test_user_u.id).each {|sr| sr.destroy!}; test_user_u.destroy!
      SchemaRight.where(user_id: test_user_d.id).each {|sr| sr.destroy!}; test_user_d.destroy!
      destroy_table_with_dependencies(added_table)
      destroy_table_with_dependencies(Table.find(test_table.id))
      Table.find(missing_table.id).destroy!                                       # Table is only set hidden by import
      Schema.find(test_schema.id).update!(topic: old_topic)
    end
  end

  # only check for not touching other schemas during import
  test 'import single schema from full export' do
    exported_data = ImportExportConfig.new.export                               # get JSON data to test for import
    schema0 = Schema.where(name: exported_data['schemas'][0]['name']).first
    org_topic = schema0.topic
    exported_data['schemas'].each {|s| s['topic'] = 'CHANGED_TOPIC'}
    run_with_current_user { ImportExportConfig.new.import_schemas(exported_data, schema_name_to_pick: schema0.name) }

    Schema.all.each do |schema|
      if schema.id == schema0.id
        assert_equal('CHANGED_TOPIC', schema.topic, 'The first schema should be updated')
      else
        assert_not_equal('CHANGED_TOPIC', schema.topic, 'The other schemas should not be updated')
      end
    end

    # Restore original state
    run_with_current_user { Schema.find(schema0.id).update!(topic: org_topic) }
  end

  test 'import all from single schema export' do
    org_exported_data = ImportExportConfig.new.export # get the whole JSON data to restore after test
    exported_data = ImportExportConfig.new.export(single_schema_name: victim_schema.name) # get JSON data for single schema to test for import
    exported_data['schemas'].each {|s| s['topic'] = 'CHANGED_TOPIC'}
    run_with_current_user { ImportExportConfig.new.import_schemas(exported_data) }  # Import the whole document

    Schema.all.each do |schema|
      if schema.id == victim_schema.id
        assert_equal('CHANGED_TOPIC', schema.topic, 'The victim_schema should be updated')
      else
        assert_not_equal('CHANGED_TOPIC', schema.topic, 'The other schemas should not be updated')
      end
    end

    SchemaRight.all.each do |sr|
      assert_equal(victim_schema.id, sr.schema_id, log_on_failure('Only schema rights for the victim_schema should remain, all others should be deleted'))
    end

    Table.where(yn_hidden: 'N').each do |t|
      assert_equal(victim_schema.id, t.schema_id, log_on_failure('Only tables for the victim_schema should remain, all others should be marked hidden'))
    end

    # Restore original state
    run_with_current_user { ImportExportConfig.new.import_schemas(org_exported_data) }
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

    run_with_current_user { ImportExportConfig.new.import_schemas(exported_data) } # Now import with valid user
    user = User.where(email: 'NON_EXISTING').first
    assert_not_nil(user, 'Missing user should be created')
    assert_equal('N', user.yn_admin, 'User should not remain admin')
    assert_equal('Y', user.yn_account_locked, 'User should not locked')

    # restore original state
    run_with_current_user do
      user.schema_rights.each{|sr| sr.destroy!}
      user.destroy!
    end
  end

  test 'import config with missing structure elements' do
    # Excpect raise of RuntimeError due to explicit raise "String" in code
    def expect_raise(msg, data)
      assert_raise(RuntimeError, "Missing #{msg} should raise own raised RuntimeError exception") do
        run_with_current_user { ImportExportConfig.new.import_schemas(data) }
      rescue Exception => e
        puts "#{e.class}:#{e.message}" unless e.instance_of? RuntimeError
        raise
      end
    end

    expect_raise('schemas and users', {})
    expect_raise('schemas', {'users' => []})
    run_with_current_user { ImportExportConfig.new.import_schemas({'schemas' => [], 'users' => []}) } # Should not raise an exception

    expect_raise('schema name', {'schemas'=>[{}], 'users'=>[]})
    expect_raise('tables array', {'schemas'=>[{ 'name'=>'HUGO'}], 'users'=>[]})
    expect_raise('schema_rights array', {'schemas'=>[{ 'name'=>victim_schema.name, 'tables'=>[]}], 'users'=>[]})  # Existing schema
    expect_raise('schema_rights array', {'schemas'=>[{ 'name'=>'HUGO', 'tables'=>[]}], 'users'=>[]})  # new schema

    # restore original state, recreate needed elements
    GlobalFixtures.repeat_initialization                                        # Create fixtures again at start of the next test
  end

  test 'import config with initialization' do
    exported_data = ImportExportConfig.new.export
    # Ensure that initialization is set for TEST_MOVEX.TABLES
    exported_schema_tables = exported_data['schemas'].select{|s| s['name'] == user_schema.name}.first['tables']
    export_schema_table = exported_schema_tables.select{|t| t['name'] == tables_table.name}.first
    export_schema_table['yn_initialization'] = 'Y'
    # Should fail because no column logs insert
    assert_raise("Should raise ActiveRecord::RecordInvalid: Validation failed: Yn initialization Table #{user_schema.name}.#{tables_table.name} should have at least one column registered for insert trigger to execute initialization!") do
      run_with_current_user { ImportExportConfig.new.import_schemas(exported_data) }
    end

    # Should not fail on existing table
    export_schema_table['columns'].first['yn_log_insert'] = 'Y'                                  # Fix previous error condition
    run_with_current_user { ImportExportConfig.new.import_schemas(exported_data) }
    existing_table = Table.find(tables_table.id)
    assert_equal('Y', existing_table.yn_initialization, log_on_failure('YN_Initialization should be set in DB for existing table'))

    # Should not fail on new table, use a table that really exists in test schema
    exported_schema_tables << {
      'name'              => 'STATISTICS',
      'yn_initialization' => 'Y',
      'columns'           => [{ 'name' => 'OPERATION', 'yn_log_insert' => 'Y'}],
    }
    run_with_current_user { ImportExportConfig.new.import_schemas(exported_data) }
    added_table = Table.where(schema_id: user_schema.id, name: 'STATISTICS').first
    assert_equal('Y', added_table.yn_initialization, log_on_failure('YN_Initialization should be set in DB for added table'))

    # restore previous test data state
    run_with_current_user do
      existing_table = Table.find(tables_table.id)                              # reread to ensure current content
      existing_table.update!(yn_initialization: 'N')
      existing_table.columns.first.update!(yn_log_insert: 'N')
      destroy_table_with_dependencies(added_table)
    end
  end
end
