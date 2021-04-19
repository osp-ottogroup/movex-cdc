class DbTriggerGeneratorOracle < Database
  attr_reader :successes, :errors, :load_sqls

  TRIGGER_NAME_PREFIX = "TRIXX_"                                                # owner of trigger is always trixx_db_user, must not be part of trigger name

  ### class methods following

  # generate trigger name from short operation (I/U/D) and schema/table
  def self.build_trigger_name(schema_id, table_id, operation)
    "#{TRIGGER_NAME_PREFIX}#{operation}_#{schema_id}_#{table_id}"
  end

  # get ActiveRecord::Result with trigger records
  def self.find_all_by_schema_id(schema_id)
    schema = Schema.find schema_id
    select_all("\
      SELECT *
      FROM   All_Triggers
      WHERE  Owner        = :owner
      AND    Table_Owner  = :table_owner
    ", {
      owner:        Trixx::Application.config.trixx_db_user,
      table_owner:  schema.name
    }
    )
  end

  # get Array of Hash with trigger info
  def self.find_all_by_table(schema_id, table_id, schema_name, table_name)
    result = []
    select_all("\
      SELECT t.Trigger_name, o.Last_DDL_Time
      FROM   All_Triggers t
      JOIN   All_Objects o ON o.Owner = t.Owner AND o.Object_Name = t.Trigger_Name AND o.Object_Type = 'TRIGGER'
      WHERE  t.Owner        = :owner
      AND    t.Table_Owner  = :table_owner
      AND    t.Table_Name   = :table_name
    ", {
      owner:        Trixx::Application.config.trixx_db_user,
      table_owner:  schema_name,
      table_name:   table_name
    }).each do |t|
      ['I', 'U', 'D'].each do |operation|                                       # check for I/U/D if trigger compares to TriXX trigger name
      if t['trigger_name'] == build_trigger_name(schema_id, table_id, operation)
        result << {
          operation:  operation,
          name:       t['trigger_name'],
          changed_at: t['last_ddl_time']
        }
      end
      end
    end
    result
  end

  def self.find_by_table_id_and_trigger_name(table_id, trigger_name)
    table  = Table.find table_id
    schema = Schema.find table.schema_id
    select_first_row("\
      SELECT *
      FROM   All_Triggers
      WHERE  Owner        = :owner
      AND    Table_Owner  = :table_owner
      AND    Table_Name   = :table_name
      AND    Trigger_Name = :trigger_name
    ", {
      owner:          Trixx::Application.config.trixx_db_user,
      table_owner:    schema.name,
      table_name:     table.name,
      trigger_name:   trigger_name
    }
    )
  end


  ### instance methods following

  def initialize(schema_id:, user_options:, dry_run:)
    @schema       = Schema.find schema_id
    @user_options = user_options
    @dry_run      = dry_run
    @successes    = []                                                          # created triggers
    @errors       = []                                                          # errors during trigger creation
    @load_sqls    = []                                                          # PL/SQL snipped for initial load
    @use_json_object  = Database.db_version >= '19.1'                           # Before 19.1 JSON_OBJECT is buggy

    @existing_triggers = Database.select_all(
      "SELECT t.Table_Name, t.Trigger_Name, t.Description, t.Trigger_Body, t.Triggering_Event, o.Status
         FROM   User_Triggers t
         JOIN   User_Objects o ON o.Object_Name = t.Trigger_Name AND o.Object_Type = 'TRIGGER'
         WHERE  t.Table_Owner = :table_owner
         AND    t.Trigger_Name LIKE '#{TRIGGER_NAME_PREFIX}%'
        ",
      {
        table_owner:  @schema.name,
      }
    )

    expected_trigger_columns = Database.select_all(
      "SELECT c.Name Column_Name,
              c.YN_Log_Insert,
              c.YN_Log_Update,
              c.YN_Log_Delete,
              t.Name Table_Name,
              t.YN_Record_TxId,
              t.Kafka_Key_Handling,
              t.Fixed_Message_Key,
              tc.Data_Type,
              tc.Nullable
       FROM   Columns c
       JOIN   Tables t ON t.ID = c.Table_ID
       LEFT OUTER JOIN DBA_Tab_Columns tc ON tc.Owner = :schema_name AND tc.Table_Name = t.Name AND tc.Column_Name = c.Name
       WHERE  t.Schema_ID = :schema_id
       AND    (c.YN_Log_Insert = 'Y' OR c.YN_Log_Update = 'Y' OR c.YN_Log_Delete = 'Y')
      ", { schema_name: @schema.name, schema_id: @schema.id}
    )

    expected_trigger_operation_filters = Database.select_all(
      "SELECT t.Name Table_Name,
              cd.Operation,
              cd.filter
       FROM   Conditions cd
       JOIN   Tables t ON t.ID = cd.Table_ID
       WHERE  t.Schema_ID = :schema_id
      ", { schema_id: @schema.id}
    )

    existing_pk_columns = Database.select_all(
      "WITH Constraints AS (SELECT /*+ NO_MERGE MATERIALIZE */ Owner, Table_Name, Constraint_Name
                            FROM   DBA_Constraints
                            WHERE  Owner       = :schema_name
                            AND    Constraint_Type = 'P'
                           )
       SELECT c.Table_Name, cc.column_name, tc.Data_Type
       FROM   Constraints c
       JOIN   DBA_Cons_Columns cc ON cc.Owner = c.Owner AND cc.Table_Name  = c.table_name AND cc.Constraint_Name = c.Constraint_Name
       JOIN   DBA_Tab_Columns tc ON tc.Owner = cc.Owner AND tc.Table_name = cc.Table_Name AND tc.Column_Name = cc.Column_Name
       ORDER BY c.Table_Name, cc.Position
     ", schema_name:     @schema.name)

    # Build structure:
    # table_name: { operation: { columns: [ {column_name:, ...} ], condition: }}
    @expected_triggers = {}
    expected_trigger_columns.each do |crec|
      raise "Column #{crec.column_name} does not exist in table #{@schema.name}.#{crec.table_name}" if crec.data_type.nil?

      unless @expected_triggers.has_key?(crec.table_name)
        @expected_triggers[crec.table_name] = {
          table_name:         crec.table_name,
          yn_record_txid:     crec.yn_record_txid,
          kafka_key_handling: crec.kafka_key_handling,
          fixed_message_key:  crec.fixed_message_key
        }
      end
      ['I', 'U', 'D'].each do |operation|
        if (operation == 'I' && crec.yn_log_insert == 'Y') ||
           (operation == 'U' && crec.yn_log_update == 'Y') ||
           (operation == 'D' && crec.yn_log_delete == 'Y')
          unless @expected_triggers[crec.table_name].has_key?(operation)
            @expected_triggers[crec.table_name][operation] = { columns: [] }
          end
          @expected_triggers[crec.table_name][operation][:columns] << {
            column_name: crec.column_name,
            data_type:   crec.data_type,
            nullable:    crec.nullable
          }
        end
      end
    end

    # Add possible conditions at operation level
    expected_trigger_operation_filters.each do |cd|
      if @expected_triggers[cd.table_name] && @expected_triggers[cd.table_name][cd.operation] # register filters only if operation has columns
        @expected_triggers[cd.table_name][cd.operation][:condition] = cd.filter
      end
    end

    # Add possible primary key columns
    existing_pk_columns.each do |pkc|
      if @expected_triggers[pkc.table_name]                                     # table should have trigger
        @expected_triggers[pkc.table_name][:pk_columns] = [] unless @expected_triggers[pkc.table_name][:pk_columns]
        @expected_triggers[pkc.table_name][:pk_columns] << {
          column_name: pkc.column_name,
          data_type:   pkc.data_type
        }
      end
    end
  end

  def generate_table_triggers(table_id:)
    table = Table.find table_id
    ['I', 'U', 'D'].each do |operation|
      drop_obsolete_triggers(table, operation)
      create_or_rebuild_trigger(table, operation)
    end
  end

  private
  def drop_obsolete_triggers(table, operation)
    @existing_triggers.select { |t|
      # filter existing triggers for considered table and operation
      t.table_name == table.name.upcase && t.triggering_event == long_operation_from_short(operation)
    }.each do |trigger|
      if trigger_expected?(table, operation) &&
         build_trigger_name(table.id, operation) == trigger.trigger_name              # existing trigger for operation has the expected name
        Rails.logger.debug("Existing trigger #{trigger.trigger_name} of table #{trigger.table_name} should persist and will not be dropped.")
      else
        Rails.logger.debug("Existing trigger #{trigger.trigger_name} of table #{trigger.table_name} is not in list of expected triggers and will be dropped.")
        exec_trigger_sql("DROP TRIGGER #{Trixx::Application.config.trixx_db_user}.#{trigger.trigger_name}", trigger.trigger_name, table)
      end
    end
  end

  # Check for existence, than compare and create
  def create_or_rebuild_trigger(table, operation)
    trigger_name = build_trigger_name(table.id, operation)
    if trigger_expected?(table, operation)
      trigger_sql = generate_trigger_sql(table, operation)
      existing_trigger = @existing_triggers.select{|t| t.trigger_name == trigger_name}.first
      # Compare possibly existing trigger with new one
      if existing_trigger.nil? ||
         trigger_sql != "CREATE OR REPLACE TRIGGER #{existing_trigger.description.gsub("\n", '')}\n#{existing_trigger.trigger_body}" ||
        existing_trigger['status'] != 'VALID'                                   # Always recreate invalid triggers because erroneous body is stored in DB
        exec_trigger_sql(trigger_sql, trigger_name, table)
        generate_load_sql(table, trigger_name) if operation == 'I' && table.yn_initialization == 'Y'
      else
        Rails.logger.debug "DbTriggerGeneratorOracle.create_or_rebuild_trigger: Trigger #{@schema.name}.#{trigger_name} not replaced because nothing has changed"
      end
    end
  end

  # Generate SQLs for trigger creation and initial data load
  # return trigger_sql
  def generate_trigger_sql(table, operation)
    columns = @expected_triggers[table.name][operation][:columns]
    trigger_sql = "CREATE OR REPLACE TRIGGER #{Trixx::Application.config.trixx_db_user}.#{build_trigger_name(table.id, operation)}"
    trigger_sql << " FOR #{long_operation_from_short(operation)}"

    if operation == 'U'
      # Fire update-trigger only if relevant columns have changed by UPDATE OF column_list
      # This prevents from switch from SQL engine to PL/SQL engine if no relevant column has changed
      #
      # UPDATE OF clob_column is not supported (ORA-25006)
      # Therefore no UPDATE OF column_list filter is possible in this case to ensure trigger fires also if only CLOB column has changed
      if columns.select{|c| c[:data_type] == 'CLOB'}.count > 0
        trigger_sql << " /* OF <column_list> suppressed because CLOBs would raise ORA-25006 */"
      else
        trigger_sql << " OF #{columns.map{|x| x[:column_name]}.join(',')}"
      end
    end

    trigger_sql << " ON #{@schema.name}.#{table.name}\n"
    trigger_sql << build_trigger_body(table, operation)
    trigger_sql
  end

  # returns trigger_body_sql
  def build_trigger_body(table, operation)
    table_config    = @expected_triggers[table.name]
    trigger_config  = table_config[operation]
    columns         = trigger_config[:columns]

    body_sql = "COMPOUND TRIGGER\n"
    body_sql << generate_declare_section(table, operation, :body)
    body_sql << "
BEFORE STATEMENT IS
BEGIN
  payload_tab.DELETE; /* remove possible fragments of previous transactions */\
  #{"\n  transaction_id := DBMS_TRANSACTION.local_transaction_id;" if table_config[:yn_record_txid] == 'Y'}
END BEFORE STATEMENT;

#{position_from_operation(operation)} EACH ROW IS
BEGIN
"
    body_sql << generate_row_section(table_config, operation, :body)
    body_sql << "\
END #{position_from_operation(operation)} EACH ROW;

AFTER STATEMENT IS
BEGIN
  Flush;
END AFTER STATEMENT;

END #{build_trigger_name(table.id, operation)};
"
    body_sql
  end

  def generate_load_sql(table, trigger_name)
    # current SCN directly after creation of insert trigger
    scn = Database.select_one "SELECT current_scn FROM V$DATABASE"
    table_config    = @expected_triggers[table.name]
    operation       = 'I'
    trigger_config  = table_config[operation]                                             # Loads columns declared for insert trigger
    columns         = trigger_config[:columns]

    load_sql = "DECLARE\n"
    load_sql << generate_declare_section(table, operation, :load)
    load_sql << "
BEGIN
  FOR rec IN (SELECT #{columns.map{|x| x[:column_name]}.join(',')}
              FROM   #{Trixx::Application.config.trixx_db_user}.#{table.name}
              AS OF SCN #{scn}
             ) LOOP
"
    load_sql << generate_row_section(table_config, operation, :load)
    load_sql << "\
  END LOOP;
  Flush;
END;
"
    @load_sqls << { table_id: table.id, table_name: table.name, sql: load_sql}

    begin                                                                       # Check if table is readable
      table.raise_if_table_not_readable_by_trixx
    rescue Exception => e
      @errors << {
        table_id:           table.id,
        table_name:         table.name,
        trigger_name:       trigger_name,
        exception_class:    e.class.name,
        exception_message:  "Table #{table.schema.name}.#{table.name} is not readable by TriXX DB user! No initial data transfer executed! #{e.message}",
        sql:                sql
      }
    end
  end

  def generate_declare_section(table, operation, mode)
    "\

TYPE Payload_Rec_Type IS RECORD (
  Payload CLOB,
  Msg_Key VARCHAR2(4000)
);
TYPE Payload_Tab_Type IS TABLE OF Payload_Rec_Type INDEX BY PLS_INTEGER;
payload_rec     Payload_Rec_Type;
payload_tab     Payload_Tab_Type;
tab_size        PLS_INTEGER;
dbuser          VARCHAR2(128) := USER;
transaction_id  VARCHAR2(100) := NULL;

PROCEDURE Flush IS
BEGIN
  FORALL i IN 1..payload_tab.COUNT
    INSERT INTO #{Trixx::Application.config.trixx_db_user}.Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Created_At, Msg_Key, Transaction_ID)
    VALUES (Event_Logs_Seq.NextVal,
            #{table.id},
            '#{operation}',
            dbuser,
            payload_tab(i).Payload,
            SYSTIMESTAMP,
            payload_tab(i).msg_key,
            transaction_id
    );
  payload_tab.DELETE;
  #{"COMMIT;" if mode == :load}
END Flush;
"
  end

  #
  def generate_row_section(table_config, operation, mode)
    trigger_config = table_config[operation]
    condition_indent = trigger_config[:condition] ? '  ' : ''                   # Number of chars for row indent
    update_indent    = operation == 'U' ? '  ' : ''

    "
  tab_size := Payload_Tab.COUNT;
  IF tab_size >= 1000 THEN
    Flush;
    tab_size := 0;
  END IF;

  #{"IF #{trigger_config[:condition]} THEN" if trigger_config[:condition]}
    #{"#{condition_indent}IF #{old_new_compare(trigger_config[:columns])} THEN" if operation == 'U'}
    #{"/* JSON_OBJECT not used here to generate JSON because it is buggy for numeric values < 0 and DB version < 19.1 */" unless @use_json_object}
    #{condition_indent}#{update_indent}payload_rec.payload := #{payload_command(table_config, operation, mode)};
  #{condition_indent}#{update_indent}payload_rec.msg_key := #{message_key_sql(table_config, operation, mode)};
  #{condition_indent}#{update_indent}payload_tab(tab_size + 1) := payload_rec;
  #{"#{condition_indent}END IF;" if operation == 'U'}
  #{"END IF;" if trigger_config[:condition]}
    "
  end

  # compare old and new values for update trigger
  def old_new_compare(columns)
    columns.map{|c|
      column_name = c[:column_name]
      result = ":old.#{column_name} != :new.#{column_name}"
      if c[:nullable] == 'Y'
        result << " OR (:old.#{column_name} IS NULL AND :new.#{column_name} IS NOT NULL)"
        result << " OR (:old.#{column_name} IS NOT NULL AND :new.#{column_name} IS NULL)"
      end
      result
    }.join(' OR ')
  end

  # generate concatenated PL/SQL-commands for payload
  # - mode: :body or :load
  def payload_command(table_config, operation, mode)
    trigger_config = table_config[operation]
    if mode == :load
      payload_command_internal(trigger_config, 'rec')
    else
      case operation
      when 'I' then payload_command_internal(trigger_config, 'new')
      when 'U' then "#{payload_command_internal(trigger_config, 'old')}||',\n'||#{payload_command_internal(trigger_config, 'new')}"
      when 'D' then payload_command_internal(trigger_config, 'old')
      else
        raise "Unknown operation #{operation}"
      end
    end
  end

  def payload_command_internal(trigger_config, old_new)
    if @use_json_object
      result = "'\"#{old_new}\": ' ||\nJSON_OBJECT(\n"
      result << trigger_config[:columns].map {|c| "'#{c[:column_name]}' VALUE :#{old_new}.#{c[:column_name]}"}.join(",\n")
      result << "\n)"
    else
      result = "'\"#{old_new}\": {'||\n"
      result << trigger_config[:columns].map {|c| "'\"#{c[:column_name]}\": '||#{convert_col(c, old_new)}"}.join("||','\n||")
      result << "||'}'"
    end
    result
  end

  # convert values to string in PL/SQL, replaced by JSON_OBJECT for old/new but still used for primary key conversion
  def convert_col(column, old_new)
    column_name = ":#{old_new}.#{column[:column_name]}"
    result = ''
    result << "CASE WHEN #{column_name} IS NULL THEN 'null' ELSE " if column[:nullable] == 'Y' # NULL must be lower case to comply JSON specification
    result << case column[:data_type]
              when 'CHAR', 'CLOB', 'NCHAR', 'NCLOB', 'NVARCHAR2', 'LONG', 'ROWID', 'UROWID', 'VARCHAR2'                 # character data types
              then "'\"'||REPLACE(#{column_name}, '\"', '\\\"')||'\"'"                        # place between double quotes "xxx" and escape double quote to \"
              when 'BINARY_DOUBLE', 'BINARY_FLOAT', 'FLOAT', 'NUMBER'                                                   # Numeric data types
              then "CASE
                    WHEN #{column_name} < 1 AND #{column_name} > 0 THEN '0'||TO_CHAR(#{column_name}, 'TM','NLS_NUMERIC_CHARACTERS=''.,''')
                    WHEN #{column_name} >-1 AND #{column_name} < 0 THEN '-0'||SUBSTR(TO_CHAR(#{column_name}, 'TM','NLS_NUMERIC_CHARACTERS=''.,'''), 2)
                    ELSE TO_CHAR(#{column_name}, 'TM','NLS_NUMERIC_CHARACTERS=''.,''')
                    END"
              when 'DATE'                         then "'\"'||TO_CHAR(#{column_name}, 'YYYY-MM-DD\"T\"HH24:MI:SS')||'\"'"
              when 'RAW'                          then "'\"'||RAWTOHEX(#{column_name})||'\"'"
              when /^TIMESTAMP\([0-9]\)$/
              then "'\"'||TO_CHAR(#{column_name}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFF')||'\"'"
              when /^TIMESTAMP\([0-9]\) WITH .*TIME ZONE$/
              then "'\"'||TO_CHAR(#{column_name}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFFTZR')||'\"'"
              else
                raise "Unsupported column type '#{column[:data_type]}' for column '#{column[:column_name]}'"
              end
    result << " END" if column[:nullable] == 'Y'
    result
  end

  # Build SQL expression for message key
  def message_key_sql(table_config, operation, mode)
    case table_config[:kafka_key_handling]
    when 'N' then 'NULL'
    when 'P' then primary_key_sql(table_config, operation, mode)
    when 'F' then "'#{table_config[:fixed_message_key]}'"
    when 'T' then "transaction_id"
    else
      raise "Unsupported Kafka key handling type '#{table_config[:kafka_key_handling]}'"
    end
  end

  # get primary key columns sql for conversion to string
  def primary_key_sql(table_config, operation, mode)
    raise "Table #{@schema.name}.#{table_config[:table_name]} does not have primary key columns, but Kafka key handling should be 'P'" if table_config[:pk_columns].nil?

    pk_accessor =
      case operation
      when 'I' then 'new'
      when 'U' then 'new'
      when 'D' then 'old'
      end
    pk_accessor = 'rec' if mode == :load

    result = "'{'||"

    result << table_config[:pk_columns]
      .map{|pkc| "'#{pkc[:column_name]}: '||#{convert_col({column_name: pkc[:column_name] , data_type: pkc[:data_type]}, pk_accessor)}" }
      .join("||','||")

    #first = true
    #table_config[:pk_columns].each do |i|
    #  result << "||'#{',' unless first} #{i['column_name']}: '||#{convert_col({column_name: i['column_name'] , data_type: i['data_type']}, pk_accessor)}"
    #  first = false
    #end
    result << "||'}'"
    result
  end


  def long_operation_from_short(operation)
    case operation
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    end
  end

  def short_operation_from_long(operation)
    case operation
    when 'INSERT' then 'I'
    when 'UPDATE' then 'U'
    when 'DELETE' then 'D'
    end
  end

  def position_from_operation(operation)
    return 'BEFORE' if operation == 'D'
    'AFTER'
  end

  # Should trigger exist here
  def trigger_expected?(table, operation)
    @expected_triggers[table.name] &&                                           # Table should have triggers
      @expected_triggers[table.name][operation]                                 # Operation has columns to trigger
  end

  # generate trigger name, use public implementation
  def build_trigger_name(table_id, operation)
    DbTriggerGeneratorOracle.build_trigger_name(@schema.id, table_id, operation)
  end

  def exec_trigger_sql(sql, trigger_name, table)
    if @dry_run
      errors = []
    else
      Rails.logger.info "Execute trigger action: #{sql}"
      ActiveRecord::Base.connection.execute(sql)
      errors = Database.select_all(
        "SELECT * FROM All_Errors WHERE Owner = :owner AND Name = :name ORDER BY Sequence",
        {
          owner:  Trixx::Application.config.trixx_db_user,
          name:   trigger_name
        }
      )
    end
    if errors.count == 0
      @successes << {
        table_id:     table.id,
        table_name:   table.name,
        trigger_name: trigger_name,
        sql:          sql
      }
    else
      errors.each do |error|
        @errors << {
          table_id:           table.id,
          table_name:         table.name,
          trigger_name:       trigger_name,
          exception_class:    "Compile error line #{error['line']} position #{error['position']}",
          exception_message:  error['text'],
          sql:                sql
        }
      end
    end
  rescue Exception => e
    ExceptionHelper.log_exception(e, "DbTriggerGeneratorOracle.exec_trigger_sql: Executing SQL:\n#{sql}")
    @errors << {
      table_id:           table.id,
      table_name:         table.name,
      trigger_name:       trigger_name,
      exception_class:    e.class.name,
      exception_message:  e.message,
      sql:                sql
    }
  end

end
