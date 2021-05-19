require 'test_helper'

class ImportExportControllerTest < ActionDispatch::IntegrationTest

  def objects_equal?(expected, actual)
    s_expected = expected&.to_s
    s_actual = actual&.to_s
    if s_expected == s_actual
      true
    else

      puts "Objects are unequal! Lengths (#{s_expected.length}, #{s_actual.length})"
      puts "Expected: #{s_expected}"
      puts "Actual:   #{s_actual}"

      pos = 0
      s_expected.split('').each do |e|
        if pos < s_actual.length && e[0] != s_actual[pos]
          puts "Difference at position #{pos}"
          puts "Expected: #{s_expected[pos, s_expected.length]}"
          puts "Actual:   #{s_actual[pos, s_actual.length]}"
          break
        end
        pos += 1
      end

      false
    end
  end

  # generate expected exported user structure as Array of Hash
  def generate_expected_users
    result = []
    columns = extract_column_names(User)
    User.all.each do |u|
      user_hash = {}
      columns.each do |c|
        user_hash[c] = u.send(c)
      end
      result << user_hash
    end
    result
  end

  # Create hash with columns of object
  def generate_export_object(exp_obj, columns)
    return_hash = {}
    columns.each do |column|
      return_hash[column] = exp_obj.send(column)
    end
    # ensure the same structure of contents like real export, especially for timestamps
    JSON.parse(JSON.pretty_generate(return_hash))
  end


  # generate expected exported schema structure as Hash
  def generate_expected_schema(schema_name)
    schema_columns = extract_column_names(Schema)
    schemas = Schema.where(name: schema_name)
    raise "No schema found for name '#{schema_name}'" if schemas.count == 0
    schema = schemas[0]
    schema_hash = generate_export_object(schema, schema_columns)

    schema_hash['tables'] = []
    table_columns = extract_column_names(Table)
    schema.tables.each do |table|
      table_hash = generate_export_object(table, table_columns)

      table_hash['columns'] = []
      column_columns = extract_column_names(Column)
      table.columns.each do |column|
        table_hash['columns'] << generate_export_object(column, column_columns)
      end

      table_hash['conditions'] = []
      condition_columns = extract_column_names(Condition)
      table.conditions.each do |condition|
        table_hash['conditions'] << generate_export_object(condition, condition_columns)
      end
      schema_hash['tables'] << table_hash
    end

    schema_hash['schema_rights'] = []
    schema_right_columns = extract_column_names(SchemaRight)
    schema.schema_rights.each do |schema_right|
      schema_rights_hash = generate_export_object(schema_right, schema_right_columns)
      schema_rights_hash['email'] = schema_right.user.email
      schema_hash['schema_rights'] << schema_rights_hash
    end

    schema_hash
  end

  def extract_column_names(ar_class)
    # extract column names without id and *_id and timestamps
    ar_class.columns.select{|c| !['id', 'created_at', 'updated_at', 'lock_version'].include?(c.name) && !c.name.match?(/_id$/)}.map{|c| c.name}
  end


  # Test Goal: Ensure that the export of all schemas generates the correct json
  test "export" do
    get "/import_export", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    Rails.logger.debug @response.body
    actual = JSON.parse(@response.body)

    expected_schemas = []
    Schema.all.each do |schema|
      expected_schemas << generate_expected_schema(schema.name)
    end

    assert objects_equal?(generate_expected_users, actual['users'])
    assert objects_equal?(expected_schemas, actual['schemas'])
  end

  # Test Goal: Ensure that the export of a single schema generates the correct json
  test "export_schema" do
    db_user = Trixx::Application.config.trixx_db_user

    get "/import_export/#{db_user}", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    Rails.logger.debug @response.body
    actual = JSON.parse(@response.body)

    assert objects_equal?(generate_expected_users, actual['users'])
    assert objects_equal?([generate_expected_schema(db_user)], actual['schemas'])
  end

  # ensure that after imporing the current state the export remains equal
  test "import_all_schemas" do
    expected_schemas = []
    Schema.all.each do |schema|
      expected_schemas << generate_expected_schema(schema.name)
    end

    post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: generate_expected_users, schemas: expected_schemas}
    assert_response :success

    # export the just imported data
    get "/import_export", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    Rails.logger.debug @response.body
    exported = JSON.parse(@response.body)

    assert objects_equal?(generate_expected_users, exported['users'])
    assert objects_equal?(expected_schemas, exported['schemas'])

    GlobalFixtures.reinitialize                                                 # load original fixtures because table-IDs have changed
  end

  # Test Goal: Ensure that a user, matched by his email, can be updated through import
  test "import_user_update" do
    assert_equal "Sandro", sandro_user.first_name
    assert_equal "Preuß", sandro_user.last_name
    assert_equal "N", sandro_user.yn_admin
    assert_equal Trixx::Application.config.trixx_db_victim_user, sandro_user.db_user
    assert_no_difference('User.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: [{email: "Sandro.Preuss@ottogroup.com", db_user: Trixx::Application.config.trixx_db_user, first_name: "Grzgorz", last_name: "Pol", yn_admin: "Y"}],
                                                                             schemas: [generate_expected_schema(Trixx::Application.config.trixx_db_user)] # use dummy schema to fulfill requirements
      }
    end
    assert_response :success

    new_user = User.where(email: 'Sandro.Preuss@ottogroup.com').first
    assert_equal "Grzgorz", new_user['first_name']
    assert_equal "Pol", new_user['last_name']
    assert_equal "Y", new_user['yn_admin']
    assert_equal Trixx::Application.config.trixx_db_user, new_user['db_user']

    GlobalFixtures.reinitialize                                                 # load original fixtures
  end

  # Test Goal: Ensure that a user can be created through import
  test "import_user_create" do
    assert_difference('User.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: [{email: "new@user.hello", db_user: Trixx::Application.config.trixx_db_victim_user, first_name: "Grzgorz", last_name: "Pol", yn_admin: "Y"}],
                                                                             schemas: [generate_expected_schema(Trixx::Application.config.trixx_db_user)] # use dummy schema to fulfill requirements
      }
    end
    assert_response :success

    new_user = User.find_by_email_case_insensitive("new@user.hello")
    assert_equal "Grzgorz", new_user['first_name']
    assert_equal "Pol", new_user['last_name']
    assert_equal "Y", new_user['yn_admin']
    assert_equal Trixx::Application.config.trixx_db_victim_user, new_user['db_user']

    GlobalFixtures.reinitialize                                                 # load original fixtures
  end

  # Test Goal: Ensure that a schema configuration can be emptied through import
  # Removal of parts are not necessary, since it is the same behaviour: as soon as a schema is in params,
  # it will be emptied completely and refilled with what is passed.
  test "import_schema_remove_all" do
    old_schema = Schema.where(name: Trixx::Application.config.trixx_db_user).first
    #assert_equal "main", old_schema.name
    assert_equal KafkaHelper.existing_topic_for_test, old_schema.topic
    assert old_schema.tables.count > 0, 'original schema should contain tables'
    assert old_schema.schema_rights.count > 0, 'original schema should contain schema rights'

    # this is the minimal schema configuration
    schema = [{name: old_schema.name, topic: "TheWeather"}, tables: [], schema_rights: []]
    assert_no_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: generate_expected_users, schemas: schema}
    end
    assert_response :success

    new_schema = Schema.where(name: Trixx::Application.config.trixx_db_user).first
    assert_equal old_schema.name, new_schema.name
    assert_equal "TheWeather", new_schema.topic
    assert_equal 0, new_schema.tables.count, 'imported schema should not have any table'
    assert_equal 0, new_schema.schema_rights.count, 'imported schema should not have any schema rights'
    Schema.find(new_schema.id).update!(old_schema.attributes.select{|key, value| key != 'lock_version'})  # Restore original state

    GlobalFixtures.reinitialize                                                 # load original fixtures
  end

  # Test Goal: Ensure that a schema import does work and fills the schema with all given data
  test "import_schema_update" do
    old_schema = Schema.where(name: Trixx::Application.config.trixx_db_user).first
    #assert_equal "main", old_schema.name

    schema = [{name: old_schema.name, topic: "TheWeather",
               tables: [{"name": "NuTable", info: "InfoText", topic: "TopicText", kafka_key_handling: "F", yn_hidden: "N", fixed_message_key: "hugo",
                         columns: [{"name": "Col1", info: "Col1Text", yn_pending: "Y", yn_log_insert: "Y", yn_log_update: "N", yn_log_delete: "N"},{"name": "Col2", info: "Col2Text", yn_pending: "N", yn_log_insert: "N", yn_log_update: "Y", yn_log_delete: "Y"}],
                         conditions: [{operation: "D", filter: "ID IS NOT nil"}, {operation: "I", filter: "ID IS nil"}]}],
               schema_rights: [{"email": "admin", info: "AdminInfo"}]}]

    assert_no_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: generate_expected_users, schemas: schema}
    end
    assert_response :success

    new_schema = Schema.where(name: Trixx::Application.config.trixx_db_user).first
    assert_equal old_schema.name, new_schema.name
    assert_equal "TheWeather", new_schema.topic
    assert_equal 1, new_schema.tables.count
    assert_equal 1, new_schema.schema_rights.count

    table1 = new_schema.tables[0]
    assert_equal 2, table1.columns.count
    assert_equal 2, table1.conditions.count
    assert_equal "NuTable", table1.name
    assert_equal "InfoText", table1.info
    assert_equal "TopicText", table1.topic
    assert_equal "F", table1.kafka_key_handling
    assert_equal "hugo", table1.fixed_message_key
    assert_equal "N", table1.yn_hidden

    col1 = table1.columns.find { |col| col.name === "Col1" }
    assert_not_nil col1
    assert_equal "Col1Text", col1.info
    # TODO yn_pending does not get set correctly, but everything else does. My suspicion: It gets overwritten on save. If so, please remove from import data and add correct assertion, seem to be "N"
    # assert_equal "Y", col1.yn_pending
    assert_equal "Y", col1.yn_log_insert
    assert_equal "N", col1.yn_log_update
    assert_equal "N", col1.yn_log_delete
    col2 = table1.columns.find { |col| col.name === "Col2" }
    assert_not_nil col2
    assert_equal "Col2Text", col2.info
    # assert_equal "Y", col1.yn_pending
    assert_equal "N", col2.yn_log_insert
    assert_equal "Y", col2.yn_log_update
    assert_equal "Y", col2.yn_log_delete

    cond_d = table1.conditions.find { |cond| cond.operation === "D" }
    assert_not_nil cond_d
    assert_equal "ID IS NOT nil", cond_d.filter
    cond_i = table1.conditions.find { |cond| cond.operation === "I" }
    assert_not_nil cond_i
    assert_equal "ID IS nil", cond_i.filter

    GlobalFixtures.reinitialize                                                 # load original fixtures
  end

  # Test Goal: Ensure that a schema import does work and fills the schema with all given data
  test "import_schema_new" do
    schema = [{name: "another", topic: "TheWeather", not_existing_column: 'Does not exist in model no more',
               tables: [{"name": "NuTable", info: "InfoText", topic: "TopicText", kafka_key_handling: "N", yn_hidden: "N",
                         columns: [{"name": "Col1", info: "Col1Text", yn_pending: "Y", yn_log_insert: "Y", yn_log_update: "N", yn_log_delete: "N"},{"name": "Col2", info: "Col2Text", yn_pending: "N", yn_log_insert: "N", yn_log_update: "Y", yn_log_delete: "Y"}],
                         conditions: [{operation: "D", filter: "ID IS NOT nil"}, {operation: "I", filter: "ID IS nil"}]}],
               schema_rights: [{"email": "admin", info: "AdminInfo"}]}]

    assert_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: generate_expected_users, schemas: schema}
    end
    assert_response :success

    new_schema = Schema.where(name: "another").first
    assert_not_nil new_schema
    assert_equal "TheWeather", new_schema.topic
    assert_equal 1, new_schema.tables.count
    assert_equal 1, new_schema.schema_rights.count

    table1 = new_schema.tables[0]
    assert_equal 2, table1.columns.count
    assert_equal 2, table1.conditions.count
    assert_equal "NuTable", table1.name
    assert_equal "InfoText", table1.info
    assert_equal "TopicText", table1.topic
    assert_equal "N", table1.kafka_key_handling
    assert_equal "N", table1.yn_hidden

    col1 = table1.columns.find { |col| col.name === "Col1" }
    assert_not_nil col1
    assert_equal "Col1Text", col1.info
    # TODO yn_pending does not get set correctly, but everything else does. My suspicion: It gets overwritten on save. If so, please remove from import data and add correct assertion, seem to be "N"
    # assert_equal "Y", col1.yn_pending
    assert_equal "Y", col1.yn_log_insert
    assert_equal "N", col1.yn_log_update
    assert_equal "N", col1.yn_log_delete
    col2 = table1.columns.find { |col| col.name === "Col2" }
    assert_not_nil col2
    assert_equal "Col2Text", col2.info
    # assert_equal "Y", col1.yn_pending
    assert_equal "N", col2.yn_log_insert
    assert_equal "Y", col2.yn_log_update
    assert_equal "Y", col2.yn_log_delete

    cond_d = table1.conditions.find { |cond| cond.operation === "D" }
    assert_not_nil cond_d
    assert_equal "ID IS NOT nil", cond_d.filter
    cond_i = table1.conditions.find { |cond| cond.operation === "I" }
    assert_not_nil cond_i
    assert_equal "ID IS nil", cond_i.filter

    GlobalFixtures.reinitialize                                                 # load original fixtures
  end
end

# TODO There could be some more tests, of which i cannot say if they make sense or not - this depends on the inner workings of trixx. Some others make sense, but might be overkill and could be omitted until Trixx makes its first million.
# 1. Test if Schema Rights are "wired" correctly. If the SchemaRight cannot be saved if not in a valid configuration, this test is not necessary
# 2. Negative Tests with invalid import data, to see how Trixx Import reacts on invalid Data.
# 3. Tests for accessing the end point with correct authentication? Right now, nothing is implemented done in that regard.
# 4. More Parameter Variations. For example, i cannot judge if it makes sense to test with other values for kafka_key_handling for the import - my guess is "no"

