class Table < ApplicationRecord
  belongs_to  :schema
  has_many    :columns
  has_many    :conditions

  # Tables that do not exist in database no more but are configured for TriXX
  attribute   :yn_deleted_in_db, :string, limit: 1, default: 'N'

  validate    :topic_in_table_or_schema
  validate    :kafka_key_handling_validate
  validate    :validate_yn_columns
  validate    :validate_unchanged_attributes
  validate    :validate_yn_initialization

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

  def kafka_key_handling_validate
    valid_kafka_key_handlings = ['N', 'P', 'F', 'T']
    unless valid_kafka_key_handlings.include? kafka_key_handling
      errors.add(:kafka_key_handling, "Invalid value '#{kafka_key_handling}', valid values are #{valid_kafka_key_handlings}")
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
  end

  def validate_yn_columns
    validate_yn_column :yn_record_txid
    validate_yn_column :yn_hidden
    validate_yn_column :yn_initialization
  end

  def validate_unchanged_attributes
    errors.add(:schema_id, "Change of schema_id not allowed!")  if schema_id_changed? && self.persisted?
    errors.add(:name, "Change of name not allowed!")            if name_changed?      && self.persisted?
  end

  def validate_yn_initialization
    if yn_initialization_changed? and yn_initialization == 'Y'
      begin
        raise_if_table_not_readable_by_trixx
      rescue Exception => e
        errors.add(:yn_initialization, "Table #{self.schema.name}.#{self.name} must be readable for initial transfer to Kafka!\n#{e.class}:#{e.message}")
      end
    end
  end

  # check if table is readable by TriXX DB user and raise exception if not
  def raise_if_table_not_readable_by_trixx
    error_msg_add = ''
    sql           = ''
    case Trixx::Application.config.trixx_db_type
    when 'ORACLE' then
      scn = Database.select_one "SELECT current_scn FROM V$DATABASE"            # Check if read and flashback is possible
      sql = "SELECT COUNT(*) FROM #{self.schema.name}.#{self.name} AS OF SCN #{scn} WHERE ROWNUM < 2"  # one row should be read physically
      error_msg_add = "FLASHBACK grant on table #{self.schema.name}.#{self.name} or FLASHBACK ANY TABLE is needed for TriXX DB user!"
    when 'SQLITE' then
      sql = "SELECT COUNT(*) FROM #{self.schema.name}.#{self.name} LIMIT 1"
    end
    Database.select_one sql
  rescue Exception => e
    msg = "#{e.class}:#{e.message} Table #{self.schema.name}.#{self.name} is not readable.\nSQL: #{sql}\n#{error_msg_add}"
    Rails.logger.error msg
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
    DbTrigger.find_all_by_table(schema_id, id, schema.name, name)
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
  def self.check_table_allowed_for_db_user(current_user:, schema_name:, table_name:, allow_for_nonexisting_table: false)
    current_user.check_user_for_valid_schema_right(Schema.where(name: schema_name).first.id)  # First check user config

    table_exists = Database.select_one("SELECT COUNT(*) FROM All_DB_Tables WHERE Owner = :owner AND Table_Name = :table_name",
                                       owner: schema_name, table_name: table_name) > 0

    return if current_user.db_user == schema_name && table_exists               # Allow maintenance for own existing tables

    return if allow_for_nonexisting_table && !table_exists                      # Allow action for non existing table without further check if requested

    case Trixx::Application.config.trixx_db_type
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
                                    owner: schema_name, db_user: current_user.db_user, table_name: table_name) > 0

      # Check if user has SELECT ANY TABLE
      return if Database.select_one("SELECT COUNT(*)
                                     FROM   DBA_Sys_Privs
                                     WHERE  Privilege = 'SELECT ANY TABLE'
                                     AND    Grantee     = :db_user",
                                    db_user: current_user.db_user) > 0

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
                                    owner: schema_name, db_user: current_user.db_user, table_name: table_name) > 0

    when 'SQLITE' then
      return if Database.select_one("SELECT COUNT(*) FROM All_DB_Tables WHERE Owner = :owner AND Table_Name = :table_name",
                                    owner: schema_name, table_name: table_name) > 0 # Table should exist
    else
      raise "Table.check_table_allowed_for_db_user: Declaration missing for #{Trixx::Application.config.trixx_db_type}"
    end
    # Raise exception if none of previous checks has returned from method
    raise "Maintenance of table #{schema_name}.#{table_name} not allowed for DB user #{current_user.db_user}"
  end
end
