class Table < ApplicationRecord
  belongs_to  :schema, optional: true  # optional: true is to avoid the extra lookup on reference for every DML. Integrity is ensured by FK constraint
  has_many    :columns
  has_many    :conditions
  has_many    :column_expressions

  # Tables that do not exist in database no more but are configured for MOVEX CDC
  attribute   :yn_deleted_in_db, :string, limit: 1, default: 'N'

  validate    :topic_in_table_or_schema
  validate    :kafka_key_handling_validate
  validate    :validate_yn_columns
  validate    :validate_unchanged_attributes
  validate    :validate_yn_initialization
  validate    :validate_yn_initialization_update, on: :update                   # allow initialization='Y' at table creation and tag columns after that
  validate    :validate_initialization_filter
  validate    :validate_yn_payload_pkey_only

  # create a table record or mark existing hidden table as visible
  # used in TablesController#create and in DbTriggerGeneratorBase#create_load_sql
  # @param [ActionController::Parameters|Hash] table_params the table parameters
  # @return [Table] the created or updated table
  def self.create_or_mark_visible(table_params)
    tables = Table.where({ schema_id: table_params[:schema_id], name: table_params[:name]})   # Check for existing hidden or not hidden table
    if tables.length > 0                                                        # table still exists
      table = tables[0]
      table.update(table_params.to_h.merge({yn_hidden: 'N'}))    # mark visible for GUI, store errors in table.errors if any
      table
    else
      table = Table.new(table_params)
      table.save                                                                # save-errors are in table.errors if any
      table
    end
  end

  # get all tables for schema where the current user has SELECT grant
  def self.all_allowed_tables_for_schema(schema_id, db_user)
    schema = Schema.find schema_id
    #Table.where({schema_id: schema_id, yn_hidden: 'N' })
    #    .where(["Name IN (SELECT Table_Name FROM Allowed_DB_Tables WHERE Owner = ? AND Grantee = ?)", schema.name, db_user])

    # Find all tables where a user is allowed to read or do not exist no more
    Table.find_by_sql([ "SELECT t.*,
                         CASE WHEN dt.Table_Name IS NULL THEN 'Y' ELSE 'N' END yn_deleted_in_db /* does not exist in DB no more */
                         FROM   Tables t
                         LEFT OUTER JOIN All_DB_Tables dt ON dt.Owner = :owner AND dt.Table_Name = t.Name
                         LEFT OUTER JOIN Allowed_DB_Tables a ON a.Table_Name = t.Name AND a.Owner = :owner AND a.Grantee = :grantee
                         WHERE  t.Schema_ID = :schema_id
                         AND    t.YN_Hidden = 'N'
                         AND    (a.Table_Name IS NOT NULL OR dt.Table_Name IS NULL) /* Show tables if allowed or physically deleted */
                        ", { owner: schema.name, grantee: db_user, schema_id: schema_id }
                      ]
    )
  end

  def topic_in_table_or_schema
    if (topic.nil? || topic == '')
      errors.add(:topic, "cannot be empty if topic of schema is also empty") if (schema.topic.nil? || schema.topic == '')
    end
  end

  VALID_KAFKA_KEY_HANDLINGS = ['N', 'P', 'F', 'T', 'E']
  def kafka_key_handling_validate
    unless Table::VALID_KAFKA_KEY_HANDLINGS.include? kafka_key_handling
      errors.add(:kafka_key_handling, "Invalid value '#{kafka_key_handling}', valid values are #{Table::VALID_KAFKA_KEY_HANDLINGS}")
    end

    if kafka_key_handling != 'F' && !(fixed_message_key.nil? || fixed_message_key == '')
      errors.add(:fixed_message_key, "Fixed message key must be empty if Kafka key handling is not 'F' (Fixed)")
    end

    if kafka_key_handling == 'F' && (fixed_message_key.nil? || fixed_message_key == '')
      errors.add(:fixed_message_key, "Fixed message key must not be empty if Kafka key handling is 'F' (Fixed)")
    end

    if kafka_key_handling == 'T' && (yn_record_txid != 'Y')
      errors.add(:kafka_key_handling, "Kafka key handling 'T' (Transaction-ID) is not possible if transaction-ID is not recorded")
    end

    if kafka_key_handling == 'E' && key_expression.nil?
      errors.add(:kafka_key_handling, "Kafka key handling 'E' (Expression) is not possible if no key expression is defined")
    end
    errors.add(:kafka_key_handling, "'Primary key' not possible because the table does not have a primary key") if self.kafka_key_handling == 'P' && pkey_columns.empty?
  end

  def validate_yn_columns
    validate_yn_column :yn_record_txid
    validate_yn_column :yn_hidden
    validate_yn_column :yn_initialization
    validate_yn_column :yn_initialize_with_flashback
    validate_yn_column :yn_payload_pkey_only
  end

  def validate_unchanged_attributes
    errors.add(:schema_id, "Change of schema_id not allowed!")  if schema_id_changed? && self.persisted?
    errors.add(:name, "Change of name not allowed!")            if name_changed?      && self.persisted?
  end

  def validate_yn_initialization
    if yn_initialization == 'Y' && (yn_initialization_changed? || yn_initialize_with_flashback_changed?)
      begin
        raise_if_table_not_readable_by_movex_cdc
      rescue Exception => e
        errors.add(:yn_initialization, "Table #{self.schema.name}.#{self.name} must be readable for initial transfer to Kafka!\n#{e.class}:#{e.message}")
      end
    end
  end

  def validate_yn_initialization_update
    # Validation should not be tested at update when table is marked as hidden
    if yn_initialization == 'Y' && yn_hidden == 'N'
      if Column.where(table_id: self.id, yn_log_insert: 'Y').count == 0
        errors.add(:yn_initialization, "Table #{self.schema.name}.#{self.name} should have at least one column registered for insert trigger to execute initialization!")
      end
    end
  end

  def validate_initialization_filter
    if initialization_filter_changed? && !initialization_filter.nil? && initialization_filter.length > 0
      sql = "SELECT COUNT(*) FROM #{self.schema.name}.#{self.name} WHERE #{initialization_filter} #{Database.result_limit_expression('limit')}"
      begin
        Database.select_one sql, {limit: 0}
      rescue Exception => e
        Rails.logger.debug('Table.validate_initialization_filter') { "#{e.class}:#{e.message} in Table.validate_initialization_filter for SQL:\n#{sql}" }
        errors.add(:initialization_filter, "Error '#{e.class}:#{e.message}' at check of initialization filter with '#{sql}'")
      end
    end
  end

  def validate_yn_payload_pkey_only
    errors.add(:yn_payload_pkey_only, "Setting not possible because the table does not have a primary key") if self.yn_payload_pkey_only == 'Y' && pkey_columns.empty?
  end

  # @return [Array] the columns names of the primary key as array
  def pkey_columns
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      sql = "SELECT cc.Column_Name
             FROM   DBA_Constraints c
             JOIN   DBA_Cons_Columns cc ON cc.Owner = c.Owner AND cc.Constraint_Name = c.Constraint_Name
             WHERE  c.Owner           = :owner
             AND    c.Table_Name      = :table_name
             AND    c.Constraint_Type = 'P'
             ORDER BY cc.Position"
      Database.select_all(sql, owner: self.schema.name, table_name: self.name).map { |row| row['column_name'] }
    when 'SQLITE' then
      sql = "SELECT * FROM #{self.schema.name}.PRAGMA_table_info(:table_name) WHERE pk > 0 ORDER BY pk"
      Database.select_all(sql, table_name: self.name).map { |row| row['name'] }
    end

  end

  # check if table is readable by MOVEX CDC's DB user and raise exception if not
  def raise_if_table_not_readable_by_movex_cdc
    error_msg_add = ''
    sql           = ''
    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      if yn_initialize_with_flashback == 'Y'
        # if current SCN is the same as after last DDL on table then ORA-01466 is raised at "SELECT FROM Tables AS OF SCN ..."
        Database.execute "BEGIN\nCOMMIT;\nCOMMIT;\nEND;"                        # ensure SCN is incremented at least once to prevent from ORA-01466

        scn = Database.select_one "SELECT current_scn FROM V$DATABASE"          # Check if read and flashback is possible
        sql = "SELECT COUNT(*) FROM #{self.schema.name}.#{self.name} AS OF SCN #{scn} WHERE ROWNUM < 2"  # one row should be read physically
        Database.execute "BEGIN\nCOMMIT;\nCOMMIT;\nEND;"                        # ensure SCN is incremented at least once to prevent from ORA-01466
        error_msg_add = "FLASHBACK grant on table #{self.schema.name}.#{self.name} or FLASHBACK ANY TABLE is needed for MOVEX CDC's DB user!"
      else
        sql = "SELECT COUNT(*) FROM #{self.schema.name}.#{self.name} WHERE ROWNUM < 2"  # one row should be read physically
        error_msg_add = "SELECT grant on table #{self.schema.name}.#{self.name} or SELECT ANY TABLE is needed for MOVEX CDC's DB user!"
      end

    when 'SQLITE' then
      sql = "SELECT COUNT(*) FROM #{self.schema.name}.#{self.name} LIMIT 1"
    end
    Database.select_one sql
  rescue Exception => e
    msg = "#{e.class}:#{e.message} Table #{self.schema.name}.#{self.name} is not readable.\nSQL:\n#{sql}\n#{error_msg_add}"
    Rails.logger.error("Table.raise_if_table_not_readable_by_movex_cdc") { msg }
    raise msg
  end

  def topic_to_use
    if topic.nil? || topic == ''
      schema.topic
    else
      topic
    end
  end

  # get array of corresponding database trigger objects as hash if exist
  def db_triggers
    DbTrigger.find_all_by_table(self)
  end

  # get oldest change date of existing trigger for every operation (I/U/D)
  # there may exist multiple triggers for one operation (BEFORE, AFTER etc.)
  def youngest_trigger_change_dates_per_operation
    youngest_change_dates = {}
    db_triggers.each do |t|
      if youngest_change_dates[t[:operation]].nil? || ( !t[:changed_at].nil? && t[:changed_at] > youngest_change_dates[t[:operation]] )
        youngest_change_dates[t[:operation]] = t[:changed_at]
      end
    end
    youngest_change_dates
  end

  # Check if maintenance of table is allowed for the current db_user
  # raise exception if not allowed
  def self.check_table_allowed_for_db_user(schema_name:, table_name:, allow_for_nonexisting_table: false)
    ApplicationController.current_user.check_user_for_valid_schema_right(Schema.where(name: schema_name).first.id)  # First check user config

    table_exists = Database.select_one("SELECT COUNT(*) FROM All_DB_Tables WHERE Owner = :owner AND Table_Name = :table_name",
                                       owner: schema_name, table_name: table_name) > 0

    return if ApplicationController.current_user.db_user == schema_name && table_exists # Allow maintenance for own existing tables

    return if allow_for_nonexisting_table && !table_exists                      # Allow action for non existing table without further check if requested

    case MovexCdc::Application.config.db_type
    when 'ORACLE' then
      # Check for public selectable tables
      return if Database.select_one("SELECT COUNT(*)
                                     FROM   DBA_Tab_Privs tp
                                     WHERE  tp.Grantee          = 'PUBLIC'
                                     AND    tp.Privilege        = 'SELECT'
                                     AND    tp.Type             = 'TABLE'
                                     AND    tp.Owner NOT IN (SELECT UserName FROM All_Users WHERE Oracle_Maintained = 'Y') /* Don't show SYS, SYSTEM etc. */
                                     AND    tp.Owner = :owner
                                     AND    tp.Table_Name = :table_name",
                                    owner: schema_name, table_name: table_name) > 0

      # Check for explicite table grants for user
      return if Database.select_one("SELECT COUNT(*)
                                     FROM   DBA_TAB_PRIVS
                                     WHERE  Privilege   = 'SELECT'
                                     AND    Type        = 'TABLE'
                                     AND    Owner       = :owner
                                     AND    Grantee     = :db_user
                                     AND    Table_Name  = :table_name",
                                    owner: schema_name, db_user: ApplicationController.current_user.db_user, table_name: table_name) > 0

      # Check if user has SELECT ANY TABLE
      return if Database.select_one("SELECT COUNT(*)
                                     FROM   DBA_Sys_Privs
                                     WHERE  Privilege = 'SELECT ANY TABLE'
                                     AND    Grantee     = :db_user",
                                    db_user: ApplicationController.current_user.db_user) > 0

      # Check for implicite table grants for users's roles
      return if Database.select_one("SELECT COUNT(*)
                                     FROM   DBA_Tab_Privs tp
                                     JOIN   (SELECT Granted_Role, CONNECT_BY_ROOT GRANTEE Grantee
                                             FROM DBA_Role_Privs
                                             CONNECT BY PRIOR Granted_Role = Grantee
                                            ) rp ON rp.Granted_Role = tp.Grantee
                                     WHERE  tp.Privilege   = 'SELECT'
                                     AND    tp.Type        = 'TABLE'
                                     AND    tp.Owner NOT IN (SELECT UserName FROM All_Users WHERE Oracle_Maintained = 'Y') /* Don't show SYS, SYSTEM etc. */
                                     AND    tp.Owner       = :owner
                                     AND    rp.Grantee     = :db_user
                                     AND    tp.Table_Name  = :table_name",
                                    owner: schema_name, db_user: ApplicationController.current_user.db_user, table_name: table_name) > 0

    when 'SQLITE' then
      return if Database.select_one("SELECT COUNT(*) FROM All_DB_Tables WHERE Owner = :owner AND Table_Name = :table_name",
                                    owner: schema_name, table_name: table_name) > 0 # Table should exist
    else
      raise "Table.check_table_allowed_for_db_user: Declaration missing for #{MovexCdc::Application.config.db_type}"
    end
    # Raise exception if none of previous checks has returned from method
    raise "Maintenance of table #{schema_name}.#{table_name} not allowed for DB user #{ApplicationController.current_user.db_user}"
  end

  def delete
    raise "Table #{self.schema.name}.#{self.name} cannot be deleted because of references! Use mark_hidden instead."
  end

  # Alternative to destroy a table because it should physically exist with its ID because old triggers may still produce event_logs with this table_id
  def mark_hidden
    ActiveRecord::Base.transaction do
      update!(yn_hidden: 'Y')
      Database.execute "UPDATE Columns SET YN_Log_Insert='N', YN_Log_Update='N', YN_Log_Delete='N' WHERE Table_ID = :id", binds: {id: self.id}
    end
  end

  # get hash with schema_name, table_name, column_name for activity_log
  def activity_structure_attributes
    {
      schema_name:  schema.name,
      table_name:   self.name,
    }
  end

  def delete
    # Ensure that all accumulated statistics are written to DB before table is deleted
    # Otherwise flush_to_db may run in error because of missing Tables record for table_id
    StatisticCounterConcentrator.get_instance.flush_to_db if Rails.env.test?
    super
  end

  def destroy!
    # Ensure that all accumulated statistics are written to DB before table is deleted
    # Otherwise flush_to_db may run in error because of missing Tables record for table_id
    StatisticCounterConcentrator.get_instance.flush_to_db if Rails.env.test?
    super
  end

end
