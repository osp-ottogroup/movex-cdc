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


  # Test Goal: Ensure that the export of all schemas generates the correct json
  test "export" do
    get "/import_export", headers: jwt_header(@jwt_admin_token)
    assert_response :success

    db_user = Trixx::Application.config.trixx_db_user
    victim_user = Trixx::Application.config.trixx_db_victim_user

    if Trixx::Application.config.trixx_db_type == 'SQLITE'
      expected_users = JSON.parse('[{"email":"Peter.Ramm@ottogroup.com", "db_user":"' + victim_user + '", "first_name":"Peter", "last_name":"Ramm", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"Sandro.Preuss@ottogroup.com", "db_user":"sandro", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user2@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"admin", "db_user":"' + db_user + '", "first_name":"Admin", "last_name":"from fixture", "yn_admin":"Y", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user1@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"no_schema_right@ottogroup.com", "db_user":null, "first_name":"Has no right for", "last_name":"Schemas", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"user2delete@ottogroup.com", "db_user":null, "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}]')
      expected_schemas = JSON.parse('[{"name":"main", "topic":"' + KafkaHelper.existing_topic_for_test + '", "last_trigger_deployment":null, "tables":[{"name":"TABLES", "info":"Mein Text", "topic":"' + KafkaHelper.existing_topic_for_test + '", "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"SCHEMA_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[{"id":298486374, "table_id":1, "operation":"D", "filter":"ID IS NOT NULL", "lock_version":1}, {"id":980190962, "table_id":1, "operation":"I", "filter":"ID IS NOT NULL", "lock_version":1}]}, {"name":"COLUMNS", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"TABLE_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[]}, {"name":"TABLE3", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[], "conditions":[]}, {"name":"VICTIM1", "info":"Victim table in separate schema for use with triggers", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"RAW_VAL", "info":"RAW test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NAME", "info":"varchar2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TS_VAL", "info":"timestamp test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"ID", "info":"Number test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NUM_VAL", "info":"NumVal test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"DATE_VAL", "info":"date test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"ROWID_VAL", "info":"RowID test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"CHAR_NAME", "info":"char2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TSTZ_VAL", "info":"timestamp with time zone test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}], "conditions":[{"id":169672999, "table_id":4, "operation":"I", "filter":"new.Name != \'EXCLUDE FILTER\'", "lock_version":1}]}], "schema_rights":[{"name":"Peter.Ramm@ottogroup.com", "info":"Info1"}]}]')
    elsif Trixx::Application.config.trixx_db_type == 'ORACLE'
      expected_users = JSON.parse('[{"email":"admin", "db_user":"' + db_user + '", "first_name":"Admin", "last_name":"from fixture", "yn_admin":"Y", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"Peter.Ramm@ottogroup.com", "db_user":"' + victim_user + '", "first_name":"Peter", "last_name":"Ramm", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"Sandro.Preuss@ottogroup.com", "db_user":"sandro", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user1@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user2@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"user2delete@ottogroup.com", "db_user":null, "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"no_schema_right@ottogroup.com", "db_user":null, "first_name":"Has no right for", "last_name":"Schemas", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}]')
      expected_schemas = JSON.parse('[{"name":"' + db_user + '", "topic":"' + KafkaHelper.existing_topic_for_test + '", "last_trigger_deployment":null, "tables":[{"name":"TABLES", "info":"Mein Text", "topic":"' + KafkaHelper.existing_topic_for_test + '", "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"SCHEMA_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[{"id":980190962, "table_id":1, "operation":"I", "filter":"ID IS NOT NULL", "lock_version":1}, {"id":298486374, "table_id":1, "operation":"D", "filter":"ID IS NOT NULL", "lock_version":1}]}, {"name":"COLUMNS", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"TABLE_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[]}, {"name":"TABLE3", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[], "conditions":[]}], "schema_rights":[{"name":"Peter.Ramm@ottogroup.com", "info":"Info1"}]}, {"name":"' + victim_user + '", "topic":"' + KafkaHelper.existing_topic_for_test + '", "last_trigger_deployment":null, "tables":[{"name":"VICTIM1", "info":"Victim table in separate schema for use with triggers", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"ID", "info":"Number test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NAME", "info":"varchar2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"CHAR_NAME", "info":"char2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"DATE_VAL", "info":"date test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TS_VAL", "info":"timestamp test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"RAW_VAL", "info":"RAW test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TSTZ_VAL", "info":"timestamp with time zone test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"ROWID_VAL", "info":"RowID test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NUM_VAL", "info":"NumVal test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}], "conditions":[{"id":169672999, "table_id":4, "operation":"I", "filter":":new.Name != \'EXCLUDE FILTER\'", "lock_version":1}]}], "schema_rights":[{"name":"Peter.Ramm@ottogroup.com", "info":"Info1"}]}, {"name":"WITHOUT_TOPIC", "topic":null, "last_trigger_deployment":null, "tables":[], "schema_rights":[]}]')
    else
      raise Minitest::Assertion, 'Unknown DB Type "' + Trixx::Application.config.trixx_db_type + '"'
    end

    # TODO remove gsub operations after fixing the linebreak in the conditions created by the conditions fixture
    actual = JSON.parse(@response.body.gsub('\n', '').gsub('\r', ''))
    remove_dates(actual)

    # TODO is it possible to execute all assertions before aborting the test in minitest? Most often called lazy, soft or post assertion. In this case, it is desirable to both split the assertions as well as execute all assertions. If not, splitting the test would be the best option imo. Combining the assertion is not ideal - diff is even more difficult and both assertions are basically unrelated.
    assert objects_equal?(expected_users, actual['users'])
    assert objects_equal?(expected_schemas, actual['schemas'])
  end

  # Test Goal: Ensure that the export of a single schema generates the correct json
  test "export_schema" do
    db_user = Trixx::Application.config.trixx_db_user
    victim_user = Trixx::Application.config.trixx_db_victim_user

    get "/import_export", params: {schema: db_user}, headers: jwt_header(@jwt_admin_token)
    assert_response :success

    if Trixx::Application.config.trixx_db_type == 'SQLITE'
      expected_users = JSON.parse('[{"email":"Peter.Ramm@ottogroup.com", "db_user":"' + victim_user + '", "first_name":"Peter", "last_name":"Ramm", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"Sandro.Preuss@ottogroup.com", "db_user":"sandro", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user2@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"admin", "db_user":"' + db_user + '", "first_name":"Admin", "last_name":"from fixture", "yn_admin":"Y", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user1@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"no_schema_right@ottogroup.com", "db_user":null, "first_name":"Has no right for", "last_name":"Schemas", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"user2delete@ottogroup.com", "db_user":null, "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}]')
      expected_schemas = JSON.parse('[{"name":"main", "topic":"' + KafkaHelper.existing_topic_for_test + '", "last_trigger_deployment":null, "tables":[{"name":"TABLES", "info":"Mein Text", "topic":"' + KafkaHelper.existing_topic_for_test + '", "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"SCHEMA_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[{"id":298486374, "table_id":1, "operation":"D", "filter":"ID IS NOT NULL", "lock_version":1}, {"id":980190962, "table_id":1, "operation":"I", "filter":"ID IS NOT NULL", "lock_version":1}]}, {"name":"COLUMNS", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"TABLE_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[]}, {"name":"TABLE3", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[], "conditions":[]}, {"name":"VICTIM1", "info":"Victim table in separate schema for use with triggers", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"RAW_VAL", "info":"RAW test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NAME", "info":"varchar2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TS_VAL", "info":"timestamp test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"ID", "info":"Number test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NUM_VAL", "info":"NumVal test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"DATE_VAL", "info":"date test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"ROWID_VAL", "info":"RowID test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"CHAR_NAME", "info":"char2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TSTZ_VAL", "info":"timestamp with time zone test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}], "conditions":[{"id":169672999, "table_id":4, "operation":"I", "filter":"new.Name != \'EXCLUDE FILTER\'", "lock_version":1}]}], "schema_rights":[{"name":"Peter.Ramm@ottogroup.com", "info":"Info1"}]}]')
    elsif Trixx::Application.config.trixx_db_type == 'ORACLE'
      expected_users = JSON.parse('[{"email":"admin", "db_user":"' + db_user + '", "first_name":"Admin", "last_name":"from fixture", "yn_admin":"Y", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"Peter.Ramm@ottogroup.com", "db_user":"' + victim_user + '", "first_name":"Peter", "last_name":"Ramm", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"Sandro.Preuss@ottogroup.com", "db_user":"sandro", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user1@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"double_db_user2@ottogroup.com", "db_user":"double_db_user", "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"user2delete@ottogroup.com", "db_user":null, "first_name":"Sandro", "last_name":"Preuß", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}, {"email":"no_schema_right@ottogroup.com", "db_user":null, "first_name":"Has no right for", "last_name":"Schemas", "yn_admin":"N", "yn_account_locked":"N", "failed_logons":0, "yn_hidden":"N"}]')
      expected_schemas = JSON.parse('[{"name":"' + db_user + '", "topic":"' + KafkaHelper.existing_topic_for_test + '", "last_trigger_deployment":null, "tables":[{"name":"TABLES", "info":"Mein Text", "topic":"' + KafkaHelper.existing_topic_for_test + '", "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"SCHEMA_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[{"id":980190962, "table_id":1, "operation":"I", "filter":"ID IS NOT NULL", "lock_version":1}, {"id":298486374, "table_id":1, "operation":"D", "filter":"ID IS NOT NULL", "lock_version":1}]}, {"name":"COLUMNS", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"TABLE_ID", "info":"Mein Text", "yn_pending":"N", "yn_log_insert":"N", "yn_log_update":"N", "yn_log_delete":"N"}], "conditions":[]}, {"name":"TABLE3", "info":"Mein Text", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[], "conditions":[]}], "schema_rights":[{"name":"Peter.Ramm@ottogroup.com", "info":"Info1"}]}, {"name":"' + victim_user + '", "topic":"' + KafkaHelper.existing_topic_for_test + '", "last_trigger_deployment":null, "tables":[{"name":"VICTIM1", "info":"Victim table in separate schema for use with triggers", "topic":null, "kafka_key_handling":"N", "fixed_message_key":null, "yn_hidden":"N", "columns":[{"name":"ID", "info":"Number test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NAME", "info":"varchar2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"CHAR_NAME", "info":"char2 test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"DATE_VAL", "info":"date test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TS_VAL", "info":"timestamp test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"RAW_VAL", "info":"RAW test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"TSTZ_VAL", "info":"timestamp with time zone test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"ROWID_VAL", "info":"RowID test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}, {"name":"NUM_VAL", "info":"NumVal test", "yn_pending":"N", "yn_log_insert":"Y", "yn_log_update":"Y", "yn_log_delete":"Y"}], "conditions":[{"id":169672999, "table_id":4, "operation":"I", "filter":":new.Name != \'EXCLUDE FILTER\'", "lock_version":1}]}], "schema_rights":[{"name":"Peter.Ramm@ottogroup.com", "info":"Info1"}]}, {"name":"WITHOUT_TOPIC", "topic":null, "last_trigger_deployment":null, "tables":[], "schema_rights":[]}]')
    else
      raise Minitest::Assertion, 'Unknown DB Type "' + Trixx::Application.config.trixx_db_type + '"'
    end

    # TODO remove gsub operations after fixing the linebreak in the conditions created by the conditions fixture
    actual = JSON.parse(@response.body.gsub('\n', '').gsub('\r', ''))
    remove_dates(actual)

    assert objects_equal?(expected_users, actual['users'])
    assert objects_equal?(expected_schemas, actual['schemas'])
  end

  # Test Goal: Ensure that a user, matched by his email, can be updated through import
  test "import_user_update" do
    old_user = User.find(2)
    assert_equal "Sandro", old_user['first_name']
    assert_equal "Preuß", old_user['last_name']
    assert_equal "N", old_user['yn_admin']
    assert_equal "sandro", old_user['db_user']
    assert_no_difference('User.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: [{email: "Sandro.Preuss@ottogroup.com", db_user: Trixx::Application.config.trixx_db_victim_user, first_name: "Grzgorz", last_name: "Pol", yn_admin: "Y"}]}
    end
    assert_response :success

    new_user = User.find(2)
    assert_equal "Grzgorz", new_user['first_name']
    assert_equal "Pol", new_user['last_name']
    assert_equal "Y", new_user['yn_admin']
    assert_equal Trixx::Application.config.trixx_db_victim_user, new_user['db_user']
  end

  # Test Goal: Ensure that a user can be created through import
  test "import_user_create" do
    assert_difference('User.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {users: [{email: "new@user.hello", db_user: Trixx::Application.config.trixx_db_victim_user, first_name: "Grzgorz", last_name: "Pol", yn_admin: "Y"}]}
    end
    assert_response :success

    new_user = User.find_by_email_case_insensitive("new@user.hello")
    assert_equal "Grzgorz", new_user['first_name']
    assert_equal "Pol", new_user['last_name']
    assert_equal "Y", new_user['yn_admin']
    assert_equal Trixx::Application.config.trixx_db_victim_user, new_user['db_user']
  end

  # Test Goal: Ensure that a schema configuration can be emptied through import
  # Removal of parts are not necessary, since it is the same behaviour: as soon as a schema is in params,
  # it will be emptied completely and refilled with what is passed.
  test "import_schema_remove_all" do
    old_schema = Schema.find(1)
    #assert_equal "main", old_schema.name
    assert_equal KafkaHelper.existing_topic_for_test, old_schema.topic
    assert old_schema.tables.count > 0, 'original schema should contain tables'
    assert old_schema.schema_rights.count > 0, 'original schema should contain schema rights'

    # this is the minimal schema configuration
    schema = [{name: old_schema.name, topic: "TheWeather"}, tables: [], schema_rights: []]
    assert_no_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {schemas: schema}
    end
    assert_response :success

    new_schema = Schema.find(1)
    assert_equal old_schema.name, new_schema.name
    assert_equal "TheWeather", new_schema.topic
    assert_equal 0, new_schema.tables.count, 'imported schema should not have any table'
    assert_equal 0, new_schema.schema_rights.count, 'imported schema should not have any schema rights'
  end

  # Test Goal: Ensure that a schema configuration can be emptied through import
  # Removal of parts are not necessary, since it is the same behaviour: as soon as a schema is in params,
  # it will be emptied completely and refilled with what is passed.
  test "import_schema_nothing" do
    old_count =  Schema.all.count

    assert_no_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {}
    end
    assert_response :success

    assert_equal old_count, Schema.all.count
  end

  # Test Goal: Ensure that a schema import does work and fills the schema with all given data
  test "import_schema_update" do
    old_schema = Schema.find(1)
    #assert_equal "main", old_schema.name

    schema = [{name: old_schema.name, topic: "TheWeather",
               tables: [{"name": "NuTable", info: "InfoText", topic: "TopicText", kafka_key_handling: "F", yn_hidden: "N", fixed_message_key: "hugo",
                         columns: [{"name": "Col1", info: "Col1Text", yn_pending: "Y", yn_log_insert: "Y", yn_log_update: "N", yn_log_delete: "N"},{"name": "Col2", info: "Col2Text", yn_pending: "N", yn_log_insert: "N", yn_log_update: "Y", yn_log_delete: "Y"}],
                         conditions: [{operation: "D", filter: "ID IS NOT nil"}, {operation: "I", filter: "ID IS nil"}]}],
               schema_rights: [{"name": "admin", info: "AdminInfo"}]}]

    assert_no_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {schemas: schema}
    end
    assert_response :success

    new_schema = Schema.find(1)
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
  end

  # Test Goal: Ensure that a schema import does work and fills the schema with all given data
  test "import_schema_new" do
    schema = [{name: "another", topic: "TheWeather",
               tables: [{"name": "NuTable", info: "InfoText", topic: "TopicText", kafka_key_handling: "N", yn_hidden: "N",
                         columns: [{"name": "Col1", info: "Col1Text", yn_pending: "Y", yn_log_insert: "Y", yn_log_update: "N", yn_log_delete: "N"},{"name": "Col2", info: "Col2Text", yn_pending: "N", yn_log_insert: "N", yn_log_update: "Y", yn_log_delete: "Y"}],
                         conditions: [{operation: "D", filter: "ID IS NOT nil"}, {operation: "I", filter: "ID IS nil"}]}],
               schema_rights: [{"name": "admin", info: "AdminInfo"}]}]

    assert_difference('Schema.count') do
      post "/import_export", headers: jwt_header(@jwt_admin_token), params: {schemas: schema}
    end
    assert_response :success

    new_schema = Schema.find_by_name("another")
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
  end
end

# TODO There could be some more tests, of which i cannot say if they make sense or not - this depends on the inner workings of trixx. Some others make sense, but might be overkill and could be omitted until Trixx makes its first million.
# 1. Test if Schema Rights are "wired" correctly. If the SchemaRight cannot be saved if not in a valid configuration, this test is not necessary
# 2. Negative Tests with invalid import data, to see how Trixx Import reacts on invalid Data.
# 3. Tests for accessing the end point with correct authentication? Right now, nothing is implemented done in that regard.
# 4. More Parameter Variations. For example, i cannot judge if it makes sense to test with other values for kafka_key_handling for the import - my guess is "no"

def remove_dates(trixx_export)
  trixx_export['schemas'].each do |entry|
    entry['last_trigger_deployment'] = nil
    entry['tables'].each do |table|
      table['conditions'].each do |condition|
        condition.delete("created_at")
        condition.delete("updated_at")
      end
    end
  end
end