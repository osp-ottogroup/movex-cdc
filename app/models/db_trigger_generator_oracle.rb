class DbTriggerGeneratorOracle < DbTriggerGeneratorBase

  ### class methods following

  # generate trigger name from short operation (I/U/D) and schema/table
  def self.build_trigger_name(table, operation)
    super(table, operation)[0,30]                                               # but no longer than 30 chars
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
      owner:        MovexCdc::Application.config.db_user,
      table_owner:  schema.name
    }
    )
  end

  # get Array of Hash with trigger info
  def self.find_all_by_table(table)
    result = []
    select_all("\
      SELECT t.Trigger_name, o.Last_DDL_Time, t.Triggering_Event
      FROM   All_Triggers t
      JOIN   All_Objects o ON o.Owner = t.Owner AND o.Object_Name = t.Trigger_Name AND o.Object_Type = 'TRIGGER'
      WHERE  t.Owner        = :owner
      AND    t.Table_Owner  = :table_owner
      AND    t.Table_Name   = :table_name
      AND    t.Trigger_Name LIKE '#{DbTriggerGeneratorBase::TRIGGER_NAME_PREFIX}%'  /* Find triggers also if name convention in MOVEX CDC has changed */
      AND    t.Triggering_Event IN ('INSERT', 'UPDATE', 'DELETE')
    ", {
      owner:        MovexCdc::Application.config.db_user,
      table_owner:  table.schema.name,
      table_name:   table.name
    }).each do |t|
      result << {
        operation:  short_operation_from_long(t['triggering_event']),
        name:       t['trigger_name'],
        changed_at: t['last_ddl_time']
      }
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
      owner:          MovexCdc::Application.config.db_user,
      table_owner:    schema.name,
      table_name:     table.name,
      trigger_name:   trigger_name
    }
    )
  end

  ### instance methods following

  def initialize(schema_id:, dry_run:)
    super(schema_id: schema_id, dry_run: dry_run)
    @use_json_object  = Database.db_version >= '19.1'                           # Before 19.1 JSON_OBJECT is buggy
  end


  private

  def build_existing_triggers_list
    @existing_triggers = Database.select_all(
      "SELECT t.Table_Name, t.Trigger_Name, t.Description, t.Trigger_Body, t.Triggering_Event, o.Status
         FROM   User_Triggers t
         JOIN   User_Objects o ON o.Object_Name = t.Trigger_Name AND o.Object_Type = 'TRIGGER'
         WHERE  t.Table_Owner = :table_owner
         AND    (   t.Trigger_Name LIKE '#{TRIGGER_NAME_PREFIX}%'
                 OR t.Trigger_Name LIKE 'TRIXX_%' /* replace former triggers from the TRIXX era by M_CDC. Remove in 2022 */
                )
        ",
      {
        table_owner:  @schema.name,
      }
    )
  end

  # Build structure for expected triggers per table and operation:
  # @return [Hash] table_name: { operation: { columns: [ {column_name:, ...} ], condition:, column_expressions: [sql:] }}
  def build_expected_triggers_list
    expected_trigger_columns = Database.select_all(
      "SELECT c.Name Column_Name,
              o.Operation,
              t.Name Table_Name,
              t.YN_Record_TxId,
              t.Kafka_Key_Handling,
              t.Fixed_Message_Key,
              tc.Data_Type,
              tc.Nullable
       FROM   Columns c
       JOIN   Tables t ON t.ID = c.Table_ID
       JOIN   (SELECT 'I' Operation FROM DUAL UNION ALL SELECT 'U' FROM DUAL UNION ALL SELECT 'D' FROM DUAL
              ) o ON (   (o.Operation = 'I' AND c.YN_Log_Insert = 'Y')
                      OR (o.Operation = 'U' AND c.YN_Log_Update = 'Y')
                      OR (o.Operation = 'D' AND c.YN_Log_Delete = 'Y')
                     )
       LEFT OUTER JOIN DBA_Tab_Columns tc ON tc.Owner = :schema_name AND tc.Table_Name = t.Name AND tc.Column_Name = c.Name
       WHERE  t.Schema_ID = :schema_id
       AND    t.YN_Hidden = 'N'
       ORDER BY t.Name, o.Operation, tc.Column_ID /* ensure stable order for trigger code comparison and unit tests */
      ", { schema_name: @schema.name, schema_id: @schema.id}
    )

    expected_trigger_operation_filters = Database.select_all(
      "SELECT t.Name Table_Name,
              cd.Operation,
              cd.filter
       FROM   Conditions cd
       JOIN   Tables t ON t.ID = cd.Table_ID
       WHERE  t.Schema_ID = :schema_id
       AND    t.YN_Hidden = 'N'
       ORDER BY t.Name, cd.Operation /* ensure stable order for trigger code comparison and unit tests */
      ", { schema_id: @schema.id}
    )

    expected_trigger_operation_expressions = Database.select_all(
      "SELECT t.Name Table_Name, ce.ID, ce.Operation, ce.sql,
              t.YN_Record_TxId, t.Kafka_Key_Handling, t.Fixed_Message_Key
       FROM   Column_Expressions ce
       JOIN   Tables t ON t.ID = ce.Table_ID
       WHERE  t.Schema_ID = :schema_id
       AND    t.YN_Hidden = 'N'
       ORDER BY ce.Table_ID, ce.Operation, ce.ID /* ensure stable order for trigger code comparison and unit tests */
      ", { schema_id: @schema.id}
    )

    existing_pk_columns = Database.select_all(
      "WITH Constraints AS (SELECT /*+ NO_MERGE MATERIALIZE */ Owner, Table_Name, Constraint_Name
                            FROM   DBA_Constraints
                            WHERE  Owner       = :schema_name
                            AND    Table_Name NOT LIKE 'BIN$%' /* exclude logically dropped tables */
                            AND    Constraint_Type = 'P'
                           )
       SELECT c.Table_Name, cc.column_name, tc.Data_Type
       FROM   Constraints c
       JOIN   DBA_Cons_Columns cc ON cc.Owner = c.Owner AND cc.Table_Name  = c.table_name AND cc.Constraint_Name = c.Constraint_Name
       JOIN   DBA_Tab_Columns tc ON tc.Owner = cc.Owner AND tc.Table_name = cc.Table_Name AND tc.Column_Name = cc.Column_Name
       ORDER BY c.Table_Name, cc.Position
     ", schema_name:     @schema.name)

    # Build structure:
    # table_name: { operation: { columns: [ {column_name:, ...} ], condition:, column_expressions: [] }}

    table_operations_by_column = expected_trigger_columns.map do |tc|
      {
        table_name:         tc.table_name,
        yn_record_txid:     tc.yn_record_txid,
        kafka_key_handling: tc.kafka_key_handling,
        fixed_message_key:  tc.fixed_message_key,
        operation:          tc.operation,
      }
    end

    table_operations_by_expression = expected_trigger_operation_expressions.map do |ce|
      {
        table_name:         ce.table_name,
        yn_record_txid:     ce.yn_record_txid,
        kafka_key_handling: ce.kafka_key_handling,
        fixed_message_key:  ce.fixed_message_key,
        operation:          ce.operation,
      }
    end

    # TODO: remove debug output
    if Rails.env.test?
      msg = "Build expected trigger list : #{expected_trigger_operation_expressions.count}"
      Rails.logger.debug('DbTriggerGeneratorOracle.build_expected_trigger_list'){ msg }
      puts msg
    end


    expected_triggers = {}

    # Mark table and operation if requested by column or expression
    (table_operations_by_column + table_operations_by_expression).each do |to|
      unless expected_triggers.has_key?(to[:table_name])
        expected_triggers[to[:table_name]] = {
          table_name:         to[:table_name],
          yn_record_txid:     to[:yn_record_txid],
          kafka_key_handling: to[:kafka_key_handling],
          fixed_message_key:  to[:fixed_message_key]
        }
      end
      unless expected_triggers[to[:table_name]].has_key?(to[:operation])
        expected_triggers[to[:table_name]][to[:operation]] = {
          columns: [],
          column_expressions: []
        }
      end
    end

    # Mark the requested columns
    expected_trigger_columns.each do |tc|
      expected_triggers[tc.table_name][tc.operation][:columns] << {
        column_name: tc.column_name,
        data_type:   tc.data_type,
        nullable:    tc.nullable
      }
    end

    # Add possible conditions at operation level
    expected_trigger_operation_filters.each do |cd|
      if expected_triggers[cd.table_name] && expected_triggers[cd.table_name][cd.operation] # register filters only if operation has columns
        expected_triggers[cd.table_name][cd.operation][:condition] = cd['filter']   # Caution: filter is a method of ActiveRecord::Result and returns an Enumerator
      end
    end

    # Add possible column expressions at operation level
    expected_trigger_operation_expressions.each do |ce|
      expected_triggers[ce.table_name][ce.operation][:column_expressions] << { sql: ce.sql, id: ce.id }
    end

    # Add possible primary key columns
    existing_pk_columns.each do |pkc|
      if expected_triggers[pkc.table_name]                                     # table should have trigger
        expected_triggers[pkc.table_name][:pk_columns] = [] unless expected_triggers[pkc.table_name][:pk_columns]
        expected_triggers[pkc.table_name][:pk_columns] << {
          column_name: pkc.column_name,
          data_type:   pkc.data_type
        }
      end
    end
    expected_triggers
  end

  # Extract column names from SQL expression and check if they exist in table
  # @param [Table] table Table object
  # @param [String] operation I|U|D
  # @return [Hash] columns of the table/operation that are used in expressions
  #   { :new|:old.colname: {
  #     column_name:,
  #     variable_name:,         /* The variable name used in record type, contains also the qualifier :new or :old */
  #     column_expression_ids:  { id: target /* 'new' or 'old' */ } /* List of column expression IDs with the target in JSON object */
  #     data_type:,
  #     precision:,
  #     scale:,
  #     nullable:
  #     }
  #   }
  def columns_from_expression(table, operation)
    if !defined?(@columns_from_expression) || @columns_from_expression.nil?
      @columns_from_expression = {}                                             # {table_name: {operation: {column_name: {data_type:, precision:, scale: }}}}

      all_tab_columns = {}                                                      #  { table_name: { column_name: { data_type: }}}
      # Get all columns of tables planned for triggers
      Database.select_all("\
        SELECT tc.Table_Name, tc.Column_Name, tc.Data_Type, tc.Nullable,
               NVL(tc.Data_Precision, tc.Char_Length) Precision, tc.Data_Scale
        FROM   DBA_Tab_Columns tc
        JOIN   Tables t ON t.Name = tc.Table_Name
        WHERE  tc.Owner = :schema_name
        AND    t.Schema_ID = :schema_id
      ", schema_name: @schema.name, schema_id: @schema.id).each do |ac|
        all_tab_columns[ac.table_name] = {} unless all_tab_columns.has_key?(ac.table_name)
        all_tab_columns[ac.table_name][ac.column_name] = {
          data_type: ac.data_type,
          precision: ac.precision,
          scale: ac.data_scale,
          nullable: ac.nullable
        }
      end

      # TODO: replace DB select with @expected_triggers to avoid double DB access
      Database.select_all("\
        SELECT ce.ID, ce.Operation, ce.sql, t.Name Table_Name
        FROM   Column_Expressions ce
        JOIN   Tables t ON t.ID = ce.Table_ID
        WHERE  t.Schema_ID = :schema_id
      ", schema_id: @schema.id).each do |ce|
        # Get all used names combined with :new or :old qualifier

        column_regex = /:new\.([a-zA-Z0-9_]+)|:old\.([a-zA-Z0-9_]+)/i
        matches = ce.sql.scan(column_regex).flatten.compact.uniq                   # get all column names used in expression

        expression_columns = []                                                 # Array of Hash with { qualifier:, column_name: }
        matches.each do |column_name|
          if ce.sql.match(/:new\.#{column_name}\b/i)  # Check for :new.column_name
            expression_columns << { qualifier: ':new', column_name: column_name.upcase, column_expression_id: ce.id }
          end
          if ce.sql.match(/:old\.#{column_name}\b/i) # Check for :old.column_name
            expression_columns << { qualifier: ':old', column_name: column_name.upcase, column_expression_id: ce.id }
          end
        end

        expression_columns.each do |c|
          raise "Column expression '#{ce.sql}' does contain a reference to not existing column by #{c[:qualifier]}.#{c[:column_name]}" unless all_tab_columns[ce.table_name].has_key?(c[:column_name])
          @columns_from_expression[ce.table_name] = {} unless @columns_from_expression.has_key?(ce.table_name)
          all_tab_column = all_tab_columns[ce.table_name][c[:column_name]]      # Data structure for column
          @columns_from_expression[ce.table_name][ce.operation] = {} unless @columns_from_expression[ce.table_name].has_key?(ce.operation)
          col_key = "#{c[:qualifier]}.#{c[:column_name]}"
          unless @columns_from_expression[ce.table_name][ce.operation].has_key?(col_key)
            @columns_from_expression[ce.table_name][ce.operation][col_key] = {
              column_name:          c[:column_name],
              variable_name:        "#{c[:qualifier][1..4]}_#{c[:column_name]}"[0..29], # Use different variable names for :old and :new, max 30 chars
              column_expression_ids: { c[:column_expression_id] => c[:qualifier][1..4] }, # List of column expression IDs with the target in JSON object
              data_type:            all_tab_column[:data_type],
              precision:            all_tab_column[:precision],
              scale:                all_tab_column[:scale],
              nullable:             all_tab_column[:nullable]
            }
          else
            @columns_from_expression[ce.table_name][ce.operation][col_key][:column_expression_ids][c[:column_expression_id]] = c[:qualifier][1..4]
          end
        end
      end
    end

    # build result for requested table
    search_operation = operation == 'i' ? 'I' : operation                       # map 'i' to 'I' for load operation
    if @columns_from_expression.has_key?(table.name) && @columns_from_expression[table.name].has_key?(search_operation)
      @columns_from_expression[table.name][search_operation]
    else
      {}
    end
  end

  # Build PL/SQL data type for column used in expressions
  # @param [Hash] col_info Hash with column info { data_type:, precision:, scale: }
  # @return [String] PL/SQL data type
  def build_expression_data_type(col_info)
    case col_info[:data_type]
    when 'CHAR'     then "CHAR(#{col_info[:precision]})"
    when 'VARCHAR2' then "VARCHAR2(#{col_info[:precision]})"
    when 'NUMBER'   then if col_info[:precision].nil? || col_info[:precision] == 0
                           "NUMBER"
                         else
                           if col_info[:scale] && col_info[:scale] > 0
                             "NUMBER(#{col_info[:precision]}, #{col_info[:scale]})"
                           else
                             "NUMBER(#{col_info[:precision]})"
                           end
                         end
    else
      col_info[:data_type]                                                      # CLOB, DATE, TIMESTAMP(x), INTERVAL ...
    end
  end

  # get the PL/SQL code for declaration of variables and types for columns needed for column expressions
  # @param [Table] table Table object
  # @param [String] operation I|U|D, operation 'i' treated as 'I' at call
  # @param [Hash] trigger_config Configuration for the trigger { columns: [], condition:, column_expressions: [] }
  # @return [String] PL/SQL code for declaration section
  def expression_types_and_arrays_sql(table, operation, trigger_config)
    code = String.new
    unless trigger_config[:column_expressions].empty?
      code << "/* Types and arrays for columns needed to build column expressions */\n"
      unless columns_from_expression(table, operation).empty?                   # This structure is not needed if there are no columns from expressions
        code << "TYPE Expression_Rec_Type IS RECORD (\n"
        code << columns_from_expression(table, operation).map do |_k, col_info|
          "  #{col_info[:variable_name]} #{ build_expression_data_type(col_info)}"
        end.join(",\n")
        code << "\n);\n"
        code << "TYPE Expression_Tab_Type IS TABLE OF Expression_Rec_Type INDEX BY PLS_INTEGER;\n"
        code << "Expression_Rec Expression_Rec_Type;\n"
        code << "Expression_Tab Expression_Tab_Type;\n"
      end
      code << "Expression_Result CLOB;\n"
      code << "Position INTEGER; /* Position for string operations */\n"
    end
    code
  end

  # Drop existing triggers for table and operation that are not expected anymore or have wrong name
  # @param [Table] table Table object
  # @param [String] operation I|U|D
  # @return [void]
  def drop_obsolete_triggers(table, operation)
    @existing_triggers.select { |t|
      # filter existing triggers for considered table and operation
      t.table_name == table.name.upcase && t.triggering_event == DbTriggerGeneratorBase.long_operation_from_short(operation)
    }.each do |trigger|
      if trigger_expected?(table, operation) &&
         build_trigger_name(table, operation) == trigger.trigger_name           # existing trigger for operation has the expected name
        Rails.logger.debug('DbTriggerGeneratorOracle.drop_obsolete_triggers'){ "Existing trigger #{trigger.trigger_name} of table #{trigger.table_name} should persist and will not be dropped." }
      else
        Rails.logger.debug('DbTriggerGeneratorOracle.drop_obsolete_triggers'){ "Existing trigger #{trigger.trigger_name} of table #{trigger.table_name} is not in list of expected triggers and will be dropped." }
        exec_trigger_sql("DROP TRIGGER #{MovexCdc::Application.config.db_user}.#{trigger.trigger_name}", trigger.trigger_name, table)
      end
    end
  end

  def check_for_physical_column_existence(table, operation)
    columns = @expected_triggers.fetch(table.name, nil)&.fetch(operation, nil)&.fetch(:columns, nil)
    unless columns.nil?
      columns.each do |c|
        raise "Column #{c[:column_name]} does not exist in table #{@schema.name}.#{table.name}" if c[:data_type].nil?
      end
    end
  end

  # Check for existence, than compare and create
  # This is the entry method for trigger generation from TriggerGeneratorBase
  # @param [Table] table Table object
  # @param [String] operation I|U|D
  # @return [void]
  def create_or_rebuild_trigger(table, operation)
    trigger_name = build_trigger_name(table, operation)
    trigger_sql = generate_trigger_sql(table, operation)
    existing_trigger = @existing_triggers.select{|t| t.trigger_name == trigger_name}.first
    # Compare possibly existing trigger with new one
    if existing_trigger.nil? ||
       trigger_sql != "CREATE OR REPLACE TRIGGER #{existing_trigger.description.gsub("\n", '')}\n#{existing_trigger.trigger_body}" || # Compare full trigger SQL syntax
      existing_trigger['status'] != 'VALID'                                   # Always recreate invalid triggers because erroneous body is stored in DB
      exec_trigger_sql(trigger_sql, trigger_name, table)
    else
      Rails.logger.debug('DbTriggerGeneratorOracle.create_or_rebuild_trigger'){ "Trigger #{@schema.name}.#{trigger_name} not replaced because nothing has changed" }
    end
  end

  # Generate SQLs for trigger creation and initial data load
  # @param [Table] table Table object
  # @param [String] operation I|U|D
  # @return [String] complete trigger SQL including CREATE OR REPLACE and body
  def generate_trigger_sql(table, operation)
    trigger_sql = "CREATE OR REPLACE TRIGGER #{MovexCdc::Application.config.db_user}.#{build_trigger_name(table, operation)}"
    trigger_sql << " FOR #{DbTriggerGeneratorBase.long_operation_from_short(operation)}"

    if operation == 'U'
      # Fire update-trigger only if relevant columns have changed by UPDATE OF column_list
      # This prevents from switch from SQL engine to PL/SQL engine if no relevant column has changed
      #
      # UPDATE OF clob_column is not supported (ORA-25006)
      # Therefore no UPDATE OF column_list filter is possible in this case to ensure trigger fires also if only CLOB column has changed
      columns = @expected_triggers[table.name][operation][:columns].dup            # real table columns
      columns_from_expression(table, 'U').each do |_k, col_info|
        if columns.select{|c| c[:column_name] == col_info[:column_name]}.count == 0 # add columns from expressions only if not already part of real table columns
          columns << {
            column_name: col_info[:column_name],
            data_type:   col_info[:data_type],
            nullable:    col_info[:nullable]
          }
        end
      end
      if columns.select{|c| c[:data_type] == 'CLOB'}.count > 0
        trigger_sql << " /* OF <column_list> suppressed because CLOBs would raise ORA-25006 */"
      else
        trigger_sql << " OF #{columns.map{|x| x[:column_name]}.join(', ')}"
      end
    end

    trigger_sql << " ON #{@schema.name}.#{table.name}\n"
    trigger_sql << build_trigger_body(table, operation)
    trigger_sql
  end

  # Create the trigger_body_sql
  # @param [Table] table Table object
  # @param [String] operation I|U|D
  # @return [String] complete trigger body SQL
  def build_trigger_body(table, operation)
    table_config    = @expected_triggers[table.name]
    trigger_config  = table_config[operation]
    columns         = trigger_config[:columns]

    body_sql = "COMPOUND TRIGGER\n".dup
    body_sql << generate_declare_section(table, operation, :body, trigger_config)
    body_sql << "
BEFORE STATEMENT IS
BEGIN
  payload_tab.DELETE; /* remove possible fragments of previous transactions */\
  #{"\n  Expression_Tab.DELETE;" unless columns_from_expression(table, operation).empty?}
  #{"\n  transaction_id := DBMS_TRANSACTION.local_transaction_id;" if table_config[:yn_record_txid] == 'Y'}
END BEFORE STATEMENT;

#{position_from_operation(operation)} EACH ROW IS
BEGIN
"
    body_sql << generate_row_section(table, table_config, operation)
    body_sql << "\
END #{position_from_operation(operation)} EACH ROW;

AFTER STATEMENT IS
BEGIN
  Flush;
END AFTER STATEMENT;

END #{build_trigger_name(table, operation)};
"
    body_sql
  end

  # Generate the PL/SQL code for initial load of existing table content
  # @param [Table] table Table object
  # @return [void]
  def create_load_sql(table)
    table_config    = @expected_triggers[table.name]
    operation       = 'i'                                                       # Lower case for initialization to distinguish between new inserts (I) and initial load (i)
    trigger_config  = table_config[operation.upcase]                            # Loads columns declared for insert trigger
    columns         = trigger_config[:columns]

    where = String.new                                                          # optional conditions
    where << "\nWHERE " if table.initialization_filter || trigger_config[:condition]
    where << "(/* initialization filter */ #{table.initialization_filter})" if table.initialization_filter
    where << "\nAND " if table.initialization_filter && trigger_config[:condition]
    # replace trigger specific :new. qualifier from in trigger condition with the full table name
    where << "(/* insert condition */ #{trigger_config[:condition].gsub(/:new./i, "#{table.schema.name}.#{table.name}.")})" if trigger_config[:condition]

    load_sql = "DECLARE\n".dup
    load_sql << generate_declare_section(table, operation, :load, trigger_config, addition: "  record_count      PLS_INTEGER := 0;") # use operation 'i' for event generation
    # use current SCN directly after creation of insert trigger if requested
    load_sql << "
BEGIN
  FOR rec IN (SELECT #{columns.map{|x| x[:column_name]}.join(',')}
              FROM   #{table.schema.name}.#{table.name} #{"AS OF SCN #{Database.select_one "SELECT current_scn FROM V$DATABASE"}" if table.yn_initialize_with_flashback == 'Y'}\
              #{where}#{"\nORDER BY #{table.initialization_order_by}" if table.initialization_order_by}
             ) LOOP
"
    # Conditions must not be included in row section because they are already part of the driving SQL
    trigger_row_section = generate_row_section(table, table_config, operation.upcase, include_conditions: false)  # generate columns for insert operation (I)
    load_sql << trigger_row_section.gsub(':new', 'rec')     # replace the record alias for insert trigger with loop variable for load sql
    load_sql << "
    record_count := record_count + 1;
  END LOOP;
  Flush;
  INSERT INTO #{MovexCdc::Application.config.db_user}.Activity_Logs(ID, User_ID, Schema_Name, Table_Name, Action, Client_IP, Created_At, Updated_At)
  VALUES (#{MovexCdc::Application.config.db_user}.Activity_Logs_Seq.NextVal,
          #{ApplicationController.current_user.id},
          '#{table.schema.name}',
          '#{table.name}',
          'Initially transferred '||record_count||' records of current table content. Filter = \"#{table.initialization_filter}\"',
          '#{ApplicationController.current_client_ip_info}',
          CURRENT_TIMESTAMP, /* Time according to client timezone setting */
          CURRENT_TIMESTAMP
  );
  COMMIT;
END;
"
    @load_sqls << { table_id: table.id, table_name: table.name, sql: load_sql}

    begin                                                                       # Check if table is readable
      table.raise_if_table_not_readable_by_movex_cdc
    rescue Exception => e
      @errors << {
        table_id:           table.id,
        table_name:         table.name,
        trigger_name:       self.build_trigger_name(table, 'I'),
        exception_class:    e.class.name,
        exception_message:  "Table #{table.schema.name}.#{table.name} is not readable by MOVEX CDC's DB user! No initial data transfer executed! #{e.message}",
        sql:                load_sql
      }
    end
  end

  # @param [Table] table Table object
  # @param [String] operation I|U|D
  # @param [Symbol] mode :body | :load
  # @param [Hash] trigger_config config for operation of table { columns: [], condition:, column_expressions: [] }
  # @param [String, nil] addition additional PL/SQL code to be added to declaration section
  # @return [String] PL/SQL code for declaration section of trigger or load SQL
  def generate_declare_section(table, operation, mode, trigger_config, addition: nil)
    "\

TYPE Payload_Rec_Type IS RECORD (
  Payload CLOB,
  Msg_Key VARCHAR2(4000)
);
TYPE Payload_Tab_Type IS TABLE OF Payload_Rec_Type INDEX BY PLS_INTEGER;
payload_rec       Payload_Rec_Type;
payload_tab       Payload_Tab_Type;
tab_size          PLS_INTEGER;
dbuser            VARCHAR2(128) := SYS_CONTEXT('USERENV', 'SESSION_USER');
transaction_id    VARCHAR2(100) := NULL;
#{expression_types_and_arrays_sql(table, operation, trigger_config)}
#{"condition_result  NUMBER;" if mode == :body && separate_condition_sql_needed?(trigger_config[:condition])}
#{addition}

PROCEDURE Flush IS
BEGIN
#{build_expression_execution_section(table, operation, trigger_config)}
  FORALL i IN 1..payload_tab.COUNT
    INSERT INTO #{MovexCdc::Application.config.db_user}.Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Created_At, Msg_Key, Transaction_ID)
    VALUES (Event_Logs_Seq.NextVal,
            #{table.id},
            '#{operation}',
            dbuser,
            payload_tab(i).Payload,
            SYSTIMESTAMP, /* time according to system timezone setting of DB */
            payload_tab(i).msg_key,
            transaction_id
    );
  payload_tab.DELETE;#{"\n  Expression_Tab.DELETE;" unless columns_from_expression(table, operation).empty?}
  #{"COMMIT;" if mode == :load}
END Flush;
"
  end

  # Build the execution of column expression SQL for each record of payload_tab
  # @param [Table] table: Table object
  # @param [String] operation: I|U|D
  # @param [Hash] trigger_config: config for operation of table { columns: [], condition:, column_expressions: [] }
  # @return [String] PL/SQL code for execution of column expressions
  def build_expression_execution_section(table, operation, trigger_config)
    # TODO: remove debug output
    if Rails.env.test?
      msg = "Build expression execution section for table #{table.name} and operation #{operation}, column expressions: #{trigger_config[:column_expressions].count}"
      Rails.logger.debug('DbTriggerGeneratorOracle.build_expression_execution_section'){ msg }
      puts msg
    end
    code = String.new
    unless trigger_config[:column_expressions].empty?
      code << "\n  /* Execute column expressions for each record */\n"
      code << "  FOR i IN 1..payload_tab.COUNT LOOP\n"
      trigger_config[:column_expressions].each do |expression|
        sql = expression[:sql].dup

        # Insert the INTO clause before "FROM"
        from_index = sql.index(/FROM/i) # Use /FROM/i for case-insensitive search
        raise "Column expression \"#{expression[:sql]}\" for table #{table.name} and operation '#{operation}' does not contain a FROM clause" if from_index.nil?
        expression_columns = columns_from_expression(table, operation)          # Columns relevant for execution of this expression
        target = determine_expression_json_object(expression, expression_columns, operation)

        sql = sql[0..from_index-1] + " INTO Expression_Result " + sql[from_index..-1]
        # replace :new and :old qualifiers with Expression_Rec.
        expression_columns.each do |full_col_name, col_info|
          sql.gsub!(/#{full_col_name}\b/i, "Expression_Tab(i).#{col_info[:variable_name]}") # \b for word boundary to avoid partial replacements
        end
        code << "\n"
        code << "    #{sql};\n"                                                 # Execute the expression SQL

        # Prepare the JSON snippet to be inserted into payload
        code << "    Expression_Result := TRIM(Expression_Result);              /* remove leading and trailing whitespaces */\n"
        code << "    IF SUBSTR(Expression_Result, 1, 1) = '{' THEN              /* Is the returned JSON structure an object? */\n"
        code << "      Expression_Result := SUBSTR(Expression_Result, 2, LENGTH(Expression_Result)-2); /* Remove the enclosing curly brackets */\n"
        code << "    ELSIF SUBSTR(Expression_Result, 1, 1) = '[' THEN           /* Is the returned JSON structure an array? */\n"
        code << "      Expression_Result := '\"#{expression_result_column_name(expression[:sql], expression_columns)}\":'||Expression_Result;\n"
        code << "    ELSIF Expression_Result IS NULL THEN                       /* Doesn't the expression return a result */\n"
        code << "      Expression_Result := '\"#{expression_result_column_name(expression[:sql], expression_columns)}\":null';\n"
        code << "    ELSE \n"
        code << "      RAISE_APPLICATION_ERROR(-20001, 'Result of column expression with ID = #{expression[:id]} for table #{table.name} and operation ''#{operation}'' is neither a JSON object nor a JSON array nor NULL!');\n"
        code << "    END IF; \n"

        # Now insert the result into the JSON payload in the correct object ("new" or "old")
        code << "    /* Insert result of column expression into object of JSON payload */\n"
        if target == 'old' && operation == 'U'                                  # special handling for update because old and new object exist
          code << "    Position := INSTR(payload_tab(i).Payload, '},\n\"new\": {');                                                    /* Position of last } of \"old\" object incl. newline and \"new\" in following line */\n"
          code << "    IF Position = 0 THEN\n"
          code << "      RAISE_APPLICATION_ERROR(-20001, 'Cannot find middle between old and new in JSON structure. Please raise an issue. Payload; '||payload_tab(i).Payload);\n"
          code << "    END IF;\n"
        else
          code << "    Position := LENGTH(payload_tab(i).Payload);                /* Position of last '}' of \"old\" or \"new\" JSON object */\n"
        end
        code << "    IF SUBSTR(payload_tab(i).Payload, Position-1, 1) != '{' THEN /* The current 'old' or 'new' object is not empty */\n"
        code << "      Expression_Result := ','||Expression_Result;             /* add leading comma if object already contains elements */\n"
        code << "    END IF;\n"
        code << "    /* Insert the expression result at the end of the according section */\n"
        code << "    payload_tab(i).Payload := SUBSTR(payload_tab(i).Payload, 1, Position -1) ||Expression_Result||SUBSTR(payload_tab(i).Payload, Position);\n"
        code << "\n"
      end
      code << "  END LOOP;\n"
    end
    code
  end

  # Determine the single column name for result of expression SQL (in case the result is a JSON array)
  # @param [String] sql the expressions SQL without INTO
  # @param [Hash] expression_columns columns for operation used in expression { :new|:old.colname: { column_name:, variable_name:, column_expression_id:, data_type:, precision:, scale:, nullable:  } }
  # @return [String] the column name to extract the JSON array from the result
  def expression_result_column_name(sql, expression_columns)
    rebound_sql = sql.dup
    # replace :new and :old qualifiers for trigger with valid bind variables
    expression_columns.each do |full_col_name, col_info|
      rebound_sql.gsub!(/#{full_col_name}\b/i, ":#{col_info[:variable_name]}") # \b for word boundary to avoid partial replacements
    end
    # ensure single quote in SQL are doubled for embedding in PL/SQL
    escaped_sql = rebound_sql.gsub(/'/, "''")

    dbms_sql_code ="\
DECLARE
  cursor_id INTEGER;
  desc_tab  DBMS_SQL.DESC_TAB;
  col_count NUMBER;
BEGIN
  cursor_id := DBMS_SQL.OPEN_CURSOR;
  DBMS_SQL.PARSE(cursor_id, '#{escaped_sql}', DBMS_SQL.NATIVE);
  DBMS_SQL.DESCRIBE_COLUMNS(cursor_id, col_count, desc_tab);
  IF col_count != 1 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Column expression SQL \"#{escaped_sql}\" does not return exactly one column but '||col_count||' columns!');
  END IF;
  :col_name := desc_tab(1).col_name;
  DBMS_SQL.CLOSE_CURSOR(cursor_id);
EXCEPTION
  WHEN OTHERS THEN
    IF DBMS_SQL.IS_OPEN(cursor_id) THEN
      DBMS_SQL.CLOSE_CURSOR(cursor_id);
    END IF;
    RAISE;
END;
"
    column_name = DatabaseOracle.exec_plsql_returning_string(dbms_sql_code, ":col_name")
    column_name
  rescue Exception => e
    Rails.logger.error('DbTriggerGeneratorOracle.expression_result_column_name'){ "Error determining column name for expression SQL '#{rebound_sql}': #{e.message}" }
    raise "DbTriggerGeneratorOracle.expression_result_column_name: Error determining column name! Ensure valid column name (<=30 chars) for expression result in SQL!\nExpression SQL '#{rebound_sql}': #{e.message}"
  end

  # determine the JSON object in payload (old or new) for column expression results
  # @param [Hash] expression column expression { sql:, column_expression_id: }
  # @param [Hash] expression_columns columns for operation used in expression { :new|:old.colname: { column_name:, variable_name:, column_expression_id:, data_type:, precision:, scale:, nullable:  } }
  # @param [String] operation I|U|D
  # @return [String] the 'old' or 'new' JSON object for the expression
  def determine_expression_json_object(expression, expression_columns, operation)
    case operation
    when 'I' then
      expression_columns.each do |full_colname, col_info|
        if col_info[:column_expression_ids].has_key?(expression[:id]) && col_info[:column_expression_ids][expression[:id]] == 'old'
          raise ":old is not supported for INSERT at #{expression[:sql]}"
        else
          return 'new'
        end
      end
      'new'                                                                     # default if no column found with :new qualifier
    when 'U' then
      retval = nil                                                              # default if no column found with :new or :old qualifier
      expression_columns.each do |full_colname, col_info|
        if col_info[:column_expression_ids].has_key?(expression[:id])
          retval = col_info[:column_expression_ids][expression[:id]] unless retval == 'new' # if both :new and :old are used, prefer :new
        end
      end
      retval || 'new'                                                           # Use new as default if no column found with :new or :old qualifier
    when 'D' then
          expression_columns.each do |full_colname, col_info|
            if col_info[:column_expression_ids].has_key?(expression[:id]) && col_info[:column_expression_ids][expression[:id]] == 'new'
              raise ":new is not supported for DELETE at #{expression[:sql]}"
            else
              return 'old'
            end
          end
          'old'                                                                 # default if no column found with :old qualifier
    end
  end

  # generate the row level code for trigger as well as for load sql
  # @param [Table] table
  # @param [Hash] table_config config for table { operation: { columns: [], condition:, column_expressions: [] }}
  # @param [String] operation I|U|D
  # @param [Boolean] include_conditions: Conditions should not be coded for load SQL because they are already checked as part of the driving SQL in this case
  # @return [String] PL/SQL code for row section of trigger or load SQL
  def generate_row_section(table, table_config, operation, include_conditions: true)
    trigger_config = table_config[operation]
    condition_indent = trigger_config[:condition] ? '  ' : ''                   # Number of chars for row indent
    update_indent    = operation == 'U' ? '  ' : ''
    row_section = "
  tab_size := Payload_Tab.COUNT;
  IF tab_size >= #{MovexCdc::Application.config.memory_collection_flush_limit} THEN
    Flush;
    tab_size := 0;
  END IF;

".dup
    if include_conditions
      row_section << "  SELECT COUNT(*) INTO Condition_Result FROM Dual WHERE #{trigger_config[:condition]};\n" if separate_condition_sql_needed?(trigger_config[:condition])
      row_section << "  IF #{condition_if_expression(trigger_config[:condition])} THEN\n" if trigger_config[:condition]
    end
    row_section << "  #{condition_indent}IF #{old_new_compare(table, trigger_config)} THEN\n" if operation == 'U'

    # Build the record with columns needed for expressions (if there are any)
    columns_from_expression(table, operation).each do |full_col_name, col_info|
      row_section << "  #{condition_indent}#{update_indent}Expression_Rec.#{col_info[:variable_name]} := #{full_col_name};\n" # full_col_name is :new.col or :old.col
    end
    unless columns_from_expression(table, operation).empty?
      row_section << "  #{condition_indent}#{update_indent}Expression_Tab(tab_size + 1) := Expression_Rec;\n"
    end

    # Build the payload record
    row_section << "  /* JSON_OBJECT not used here to generate JSON because it is buggy for numeric values < 0 and DB version < 19.1 */\n" unless @use_json_object
    row_section << "  #{condition_indent}#{update_indent}payload_rec.payload := #{payload_command(table_config, operation, "  #{condition_indent}#{update_indent}")};\n"
    row_section << "  #{condition_indent}#{update_indent}payload_rec.msg_key := #{message_key_sql(table_config, operation)};\n"
    row_section << "  #{condition_indent}#{update_indent}payload_tab(tab_size + 1) := payload_rec;\n"
    row_section << "  #{condition_indent}END IF;\n" if operation == 'U'
    row_section << "  END IF;\n" if trigger_config[:condition] && include_conditions
    row_section
  end

  # compare old and new values for update trigger
  # @param [Table] table Table object
  # @param [Hash] trigger_config config for operation of table { columns: [], condition:, column_expressions: [] }
  # @return [String] PL/SQL expression for comparison of old and new values
  def old_new_compare(table, trigger_config)
    columns = {}
    # Add all columns used in trigger
    trigger_config[:columns].each do |column|
      columns[column[:column_name]] = { nullable: column[:nullable] }  # use hash to avoid duplicate column names
    end

    # Add all columns used in expressions
    columns_from_expression(table, 'U').each do |_k, col_info|
      columns[col_info[:column_name]] = { nullable: col_info[:nullable] } unless columns.has_key?(col_info[:column_name])
    end

    columns.each do |column_name, column|
      column[:result] = ":old.#{column_name} != :new.#{column_name}".dup
      if column[:nullable] == 'Y'
        column[:result] << " OR (:old.#{column_name} IS NULL AND :new.#{column_name} IS NOT NULL)"
        column[:result] << " OR (:old.#{column_name} IS NOT NULL AND :new.#{column_name} IS NULL)"
      end
    end

    columns.map{|_name, col| col[:result] }.join(' OR ')
  end

  # generate concatenated PL/SQL-commands for payload
  # - mode: :body or :load
  def payload_command(table_config, operation, indent)
    trigger_config = table_config[operation]
    case operation
    when 'I' then payload_command_internal(trigger_config, 'new', indent)
    # !!! the syntax of the end of of the 'old' object and start of 'new' object must be stable because it is used to find the position in PL/SQL for inserting column expression results in build_expression_execution_section !!!
    when 'U' then "#{payload_command_internal(trigger_config, 'old', indent)}||',\n'||#{payload_command_internal(trigger_config, 'new', indent)}"
    when 'D' then payload_command_internal(trigger_config, 'old', indent)
    else
      raise "Unknown operation #{operation}"
    end
  end

  def payload_command_internal(trigger_config, old_new, indent)
    if @use_json_object
      result = "'\"#{old_new}\": ' ||"
      if trigger_config[:columns].empty?                                        # empty object if no columns defined
        result << "'{}'"                                                        # JSON_OBJECT in PL/SQL < 23ai raises for empty column list PLS-00103: Encountered the symbol ")" when expecting one of the following:
      else
        result << "\n#{indent}JSON_OBJECT(\n"
        result << trigger_config[:columns].map {|c| "  #{indent}'#{c[:column_name]}' VALUE #{convert_col_json_object(c, old_new)}"}.join(",\n")
        result << "\n#{indent})"
      end
    else
      result = "'\"#{old_new}\": {'||\n"
      result << trigger_config[:columns].map {|c| "  #{indent}'\"#{c[:column_name]}\": '||#{convert_col(c, old_new)}"}.join("||','\n||")
      result << "#{indent}||'}'"
    end
    result
  end

  # Convert columns that are not supported by JSON_OBJECT (ORA-40654)
  # @param column [Hash] {column_name:, data_type:}
  # @param old_new [String] 'old' or 'new'
  # @return [String] SQL expression for column
  def convert_col_json_object(column, old_new)
    column_name = ":#{old_new}.#{column[:column_name]}"
    case column[:data_type]
    when 'ROWID', 'UROWID' then "ROWIDTOCHAR(#{column_name})"                   # ROWID is not supported by JSON_OBJECT (ORA-40654)
    when 'RAW' then "RAWTOHEX(:#{old_new}.#{column[:column_name]})"             # Catch PLS-00306: wrong number or types of arguments
    else
      column_name                                                               # use column as is, no conversion needed
    end
  end

  # convert values to string in PL/SQL, replaced by JSON_OBJECT for old/new but still used for primary key conversion
  # @param [Hash] column column definition {:column_name, :data_type, :nullable, :data_length, :data_precision, :data_scale}
  # @param [String] old_new 'old' or 'new'
  # @return [String] PL/SQL expression to convert column value to string
  def convert_col(column, old_new)
    column_name = ":#{old_new}.#{column[:column_name]}"
    result = String.new
    result << "CASE WHEN #{column_name} IS NULL THEN 'null' ELSE " if column[:nullable] == 'Y' # NULL must be lower case to comply JSON specification
    result << case column[:data_type]
              when 'CHAR', 'CLOB', 'NCHAR', 'NCLOB', 'NVARCHAR2', 'LONG', 'VARCHAR2'                 # character data types
              then "'\"'||REPLACE(#{column_name}, '\"', '\\\"')||'\"'"                        # place between double quotes "xxx" and escape double quote to \"
              when 'BINARY_DOUBLE', 'BINARY_FLOAT', 'FLOAT', 'NUMBER'                                                   # Numeric data types
              then "CASE
                    WHEN #{column_name} < 1 AND #{column_name} > 0 THEN '0'||TO_CHAR(#{column_name}, 'TM','NLS_NUMERIC_CHARACTERS=''.,''')
                    WHEN #{column_name} >-1 AND #{column_name} < 0 THEN '-0'||SUBSTR(TO_CHAR(#{column_name}, 'TM','NLS_NUMERIC_CHARACTERS=''.,'''), 2)
                    ELSE TO_CHAR(#{column_name}, 'TM','NLS_NUMERIC_CHARACTERS=''.,''')
                    END"
              when 'DATE'                         then "'\"'||TO_CHAR(#{column_name}, 'YYYY-MM-DD\"T\"HH24:MI:SS')||'\"'"
              when 'ROWID', 'UROWID'              then "'\"'||ROWIDTOCHAR(#{column_name})||'\"'"
              when 'RAW'                          then "'\"'||RAWTOHEX(#{column_name})||'\"'"
              when /^TIMESTAMP\([0-9]\)$/
              then "'\"'||TO_CHAR(#{column_name}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFF', 'NLS_NUMERIC_CHARACTERS=''.,''')||'\"'"
              when /^TIMESTAMP\([0-9]\) WITH .*TIME ZONE$/
              then "'\"'||TO_CHAR(#{column_name}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFFTZR', 'NLS_NUMERIC_CHARACTERS=''.,''')||'\"'"
              else
                raise "Unsupported column type '#{column[:data_type]}' for column '#{column[:column_name]}'"
              end
    result << " END" if column[:nullable] == 'Y'
    result
  end

  # Build SQL expression for message key
  def message_key_sql(table_config, operation)
    case table_config[:kafka_key_handling]
    when 'N' then 'NULL'
    when 'P' then primary_key_sql(table_config, operation)
    when 'F' then "'#{table_config[:fixed_message_key]}'"
    when 'T' then "transaction_id"
    else
      raise "Unsupported Kafka key handling type '#{table_config[:kafka_key_handling]}'"
    end
  end

  # get primary key columns sql for conversion to string
  def primary_key_sql(table_config, operation)
    raise "Table #{@schema.name}.#{table_config[:table_name]} does not have primary key columns, but Kafka key handling should be 'P'" if table_config[:pk_columns].nil?

    pk_accessor =
      case operation
      when 'I' then 'new'
      when 'U' then 'new'
      when 'D' then 'old'
      end

    result = "'{'||".dup
    result << table_config[:pk_columns]
      .map{|pkc| "'\"#{pkc[:column_name]}\": '||#{convert_col({column_name: pkc[:column_name] , data_type: pkc[:data_type]}, pk_accessor)}" }
      .join("||','||")
    result << "||'}'"
    result
  end

  def position_from_operation(operation)
    return 'BEFORE' if operation == 'D'
    'AFTER'
  end

  # generate trigger name, use public implementation
  def build_trigger_name(table, operation)
    DbTriggerGeneratorOracle.build_trigger_name(table, operation)
  end

  def exec_trigger_sql(sql, trigger_name, table)
    if @dry_run
      errors = []
    else
      Rails.logger.info('DbTriggerGeneratorOracle.exec_trigger_sql'){ "Execute trigger action: #{sql}" }
      Database.exec_unprepared(sql)
      errors = Database.select_all(
        "SELECT * FROM All_Errors WHERE Owner = :owner AND Name = :name ORDER BY Sequence",
        {
          owner:  MovexCdc::Application.config.db_user,
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
      Database.execute "DROP TRIGGER #{trigger_name}"                           # Remove erroneous trigger to ensure proper DML on table
      error_text = String.new
      errors.each do |error|
        error_text << "Line #{error['line']} position #{error['position']}: #{error['text']}\n"
      end
      @errors << {
        table_id:           table.id,
        table_name:         table.name,
        trigger_name:       trigger_name,
        exception_class:    "PL/SQL compile error",
        exception_message:  error_text,
        sql:                sql
      }
    end
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'DbTriggerGeneratorOracle.exec_trigger_sql', additional_msg: "Executing SQL:\n#{sql}")
    @errors << {
      table_id:           table.id,
      table_name:         table.name,
      trigger_name:       trigger_name,
      exception_class:    e.class.name,
      exception_message:  e.message,
      sql:                sql
    }
  end

  # if condition contains a subselect then execution in separate SQL from DUAL is needed to workaround PLS-00405
  def separate_condition_sql_needed?(condition)
    !condition.nil? && !condition.upcase['SELECT'].nil?
  end

  # if condition is executed in separate SQL then use result of SQL in IF, else direct use of condition in IF
  def condition_if_expression(condition)
    if separate_condition_sql_needed?(condition)
      "condition_result > 0"
    else
      condition
    end
  end
end
