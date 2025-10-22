class DbTriggerGeneratorSqlite < DbTriggerGeneratorBase

  ### class methods following

  # get ActiveRecord::Result with trigger records
  def self.find_all_by_schema_id(schema_id)
    select_all("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type = 'trigger'
    ")
  end

  def self.find_all_by_table(table)
    result = []
    select_all("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type     = 'trigger'
      AND    tbl_name = :table_name
    ", {table_name:   table.name}).each do |t|
      operation = t['sql'].split[3]                                             # CREATE TRIGGER M_CDC_I_784_3_421_509 INSERT ...
      result << {
        operation:  short_operation_from_long(operation),
        name:       t['name'],
        changed_at: nil
      }
    end
    result
  end

  def self.find_by_table_id_and_trigger_name(table_id, trigger_name)
    select_first_row("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type = 'trigger'
    ")
    # TODO: Filter on table and trigger
  end

  ### instance methods following

  def initialize(schema_id:, dry_run:)
    super(schema_id: schema_id, dry_run: dry_run)
  end

  private

  def build_existing_triggers_list
    Database.select_all(
      "SELECT Name trigger_name, Tbl_Name table_name, SQL,
               CASE
               WHEN INSTR(sql, 'INSERT ON') > 0 THEN 'I'
               WHEN INSTR(sql, 'UPDATE ON') > 0 THEN 'U'
               WHEN INSTR(sql, 'DELETE ON') > 0 THEN 'D'
               END operation
         FROM   SQLite_Master
         WHERE  Type = 'trigger'
         AND    Name LIKE '#{TRIGGER_NAME_PREFIX}%'
        "
    )
  end

  def build_expected_triggers_list
    expected_trigger_columns = Database.select_all(
      "SELECT c.Name column_name,
              c.YN_Log_Insert,
              c.YN_Log_Update,
              c.YN_Log_Delete,
              t.Name table_name
       FROM   Columns c
       JOIN   Tables t ON t.ID = c.Table_ID
       WHERE  t.Schema_ID = :schema_id
       AND    (c.YN_Log_Insert = 'Y' OR c.YN_Log_Update = 'Y' OR c.YN_Log_Delete = 'Y')
       AND    t.YN_Hidden = 'N'
      ", { schema_id: @schema.id}
    )

    expected_trigger_operation_expressions = Database.select_all(
      "SELECT t.Name table_name, ce.id, ce.operation, ce.sql
       FROM   Column_Expressions ce
       JOIN   Tables t ON t.ID = ce.Table_ID
       WHERE  t.Schema_ID = :schema_id
       AND    t.YN_Hidden = 'N'
       ORDER BY ce.Table_ID, ce.Operation, ce.ID /* ensure stable order for trigger code comparison and unit tests */
      ", { schema_id: @schema.id}
    )

    expected_trigger_operation_filters = Database.select_all(
      "SELECT t.Name table_name,
              cd.Operation,
              cd.filter
       FROM   Conditions cd
       JOIN   Tables t ON t.ID = cd.Table_ID
       WHERE  t.Schema_ID = :schema_id
       AND    t.YN_Hidden = 'N'
      ", { schema_id: @schema.id}
    )

    # Build structure:
    # table_name: { operation: { columns: [ {column_name:, ...} ], condition: }}
    expected_triggers = {}

    # Create table and operation entries, add columns by columns
    expected_trigger_columns.each do |crec|
      unless expected_triggers.has_key?(crec.table_name)
        expected_triggers[crec.table_name] = {
          table_name:         crec.table_name
        }
      end
      ['I', 'U', 'D'].each do |operation|
        if (operation == 'I' && crec.yn_log_insert == 'Y') ||
          (operation == 'U' && crec.yn_log_update == 'Y') ||
          (operation == 'D' && crec.yn_log_delete == 'Y')
          unless expected_triggers[crec.table_name].has_key?(operation)
            expected_triggers[crec.table_name][operation] = { columns: [], column_expressions: [] }
          end
          expected_triggers[crec.table_name][operation][:columns] << {
            column_name: crec.column_name,
          }
        end
      end
    end

    # Add missing table/operation entries for operations with column expressions only
    expected_trigger_operation_expressions.each do |ce|
      expected_triggers[ce.table_name] = { table_name: ce.table_name } unless expected_triggers.has_key?(ce.table_name)
      unless expected_triggers[ce.table_name].has_key?(ce.operation)
        expected_triggers[ce.table_name][ce.operation] = { columns: [], column_expressions: [] }
      end
      expected_triggers[ce.table_name][ce.operation][:column_expressions] << { sql: ce.sql, id: ce.id  } # Caution: id is needed to ensure stable order for trigger code comparison and unit tests
    end

    # Add possible conditions at operation level
    expected_trigger_operation_filters.each do |cd|
      if expected_triggers[cd.table_name] && expected_triggers[cd.table_name][cd.operation]  # register filters only if operation has columns
        expected_triggers[cd.table_name][cd.operation][:condition] = cd['filter']  # Caution: filter is a method of ActiveRecord::Result and returns an Enumerator
      end
    end
    expected_triggers
  end

  def drop_obsolete_triggers(table, operation)
    @existing_triggers.select{|t|
      t.table_name == table.name && t.operation == operation
    }.each do |t|
      if !@expected_triggers.has_key?(table.name) || !@expected_triggers[table.name].has_key?(operation)
        Rails.logger.debug('DbTriggerGeneratorOracle.drop_obsolete_triggers'){ "Existing trigger  #{table.name}.#{t.trigger_name} not expected in config, drop to remove" }
        exec_trigger_sql("DROP TRIGGER #{t.trigger_name}", t.trigger_name, table)       # Remove existing trigger
      else
        Rails.logger.debug('DbTriggerGeneratorOracle.drop_obsolete_triggers'){ "Existing trigger #{table.name}.#{t.trigger_name} expected in config, not dropped" }
      end
    end
  end

  def check_for_physical_column_existence(table, operation)
    columns = @expected_triggers.fetch(table.name, nil)&.fetch(operation, nil)&.fetch(:columns, nil)
    unless columns.nil?
      # Find matching type and notnull for trigger columns
      Database.select_all("PRAGMA table_info(#{table.name})").each do |table_column|
        columns.each do |trigger_column|
          if table_column.name.upcase == trigger_column[:column_name].upcase
            trigger_column[:type]     = table_column.type
            trigger_column[:notnull]  = table_column.notnull
          end
        end
      end

      columns.each do |trigger_column|
        raise "Column #{trigger_column[:column_name]} does not exist in table #{@schema.name}.#{table.name}" if trigger_column[:type].nil?
      end
    end
  end

  def create_or_rebuild_trigger(table, operation)
    trigger_name    = build_trigger_name(table, operation)
    create_sql = "#{build_trigger_header(table, operation)}\n#{build_trigger_body(table, operation) }"
    existing_trigger = @existing_triggers.select{|t| t.table_name == table.name && t.operation == operation }.first
    if existing_trigger
      if create_sql != "#{existing_trigger.sql};"                         # Trigger code has changed
        exec_trigger_sql("DROP TRIGGER #{existing_trigger.trigger_name}", existing_trigger.trigger_name, table)       # Remove existing trigger
        exec_trigger_sql(create_sql, trigger_name, table)                 # create trigger again
      end
    else
      exec_trigger_sql(create_sql, trigger_name, table)                   # create new trigger
    end
  end

  def build_trigger_header(table, operation)
    table_config    = @expected_triggers[table.name]
    trigger_config  = table_config[operation]
    trigger_name = build_trigger_name(table, operation)
    old_new_compare_list = operation == 'U' ? old_new_compare(trigger_config[:columns]) : ''

    result = "CREATE TRIGGER #{trigger_name} #{DbTriggerGeneratorBase.long_operation_from_short(operation)}"
    result << " ON #{table.name} FOR EACH ROW"
    result << " WHEN " if trigger_config[:condition] || !old_new_compare_list.empty?
    result << " (#{trigger_config[:condition]})" if trigger_config[:condition]
    result << " AND " if trigger_config[:condition] && !old_new_compare_list.empty?
    result << " (#{old_new_compare_list}) " unless old_new_compare_list.empty?
    result
  end

  # Build trigger code from hash
  # @param [Table] table table object
  # @param [String] operation 'I', 'U', 'D'
  def build_trigger_body(table, operation)
    table_config    = @expected_triggers[table.name]
    trigger_config  = table_config[operation]

    accessors =
      case operation
      when 'I' then ['new']
      when 'U' then ['old', 'new']
      when 'D' then ['old']
      end

    payload = String.new
    accessors.each do |accessor|
      payload << "\"#{accessor}\": #{payload_json(table, trigger_config, accessor, operation: operation)}"
      payload << "," if accessors.length == 2 && accessor == 'old'
    end

    "\
BEGIN
  INSERT INTO Event_Logs(Table_ID, Operation, DBUser, Created_At, Payload, Msg_Key, Transaction_ID)
  VALUES (#{table.id},
          '#{operation}',
          'main',
           strftime('%Y-%m-%d %H-%M-%f','now'),
          '#{payload}',
           #{message_key_sql(table, operation)},
           #{table.yn_record_txid == 'Y' ? "'Dummy Tx-ID'" : "NULL" }
  );
END;"
  end

  # Build JSON payload for new or old values
  # @param table [Table] table object
  # @param trigger_config [Hash] configuration for trigger { }
  # @param accessor [String | NilClass] 'new', 'old' or nil for initialization
  # @param operation [String] 'I', 'U', 'D' or 'i' for initialization
  # @return [String] SQL expression for JSON payload
  def payload_json(table, trigger_config, accessor, operation:)
    columns = trigger_config[:columns]
    if table.yn_payload_pkey_only == 'Y'                                        # only primary key columns in payload requested
      columns = trigger_config[:columns].select{|c| table.pkey_columns.include?(c[:column_name]) } # only primary key columns
      table.pkey_columns.each do |pkc|
        raise "PKey column #{table.name}.#{pkc} needs to be checked for operation '#{operation}' if only primary key columns in payload are expected" unless columns.map{|c|c[:column_name]}.include?(pkc)
      end
    end

    json = "{".dup
    json << columns.map{|c| "\"#{c[:column_name]}\": '||#{convert_col(c, accessor)}||'"}.join(",\n")
    expressions_to_use = trigger_config[:column_expressions].select {|ce| place_expression_in_section?(ce[:sql], accessor, operation) }
    unless expressions_to_use.empty?
      json << ",\n" unless columns.empty?
      json << expressions_to_use
                .sort_by{|ce| ce[:id]}
                .map{|ce| prepare_column_expressions(ce[:sql], operation)}
                .join(",\n")
    end
    json << "}"
    json
  end

  # Check if the expression should be placed in the section
  # @param expression [String] SQL expression from Column_Expressions
  # @param accessor [String | NilClass] 'new', 'old' or nil for initialization
  # @param operation [String] 'I', 'U', 'D' or 'i' for initialization
  # @return [Boolean] true if expression should be placed in trigger code
  def place_expression_in_section?(expression, accessor, operation)
    return true unless operation == 'U'
    if accessor == 'new'
      !expression.match(/old\./i) || expression.match(/new\./i)                 # new section, expression must not contain old. or also new.
    elsif accessor == 'old'
      expression.match(/old\./i) && !expression.match(/new\./i)                 # old section, expression must conatin old. but not new.
    else
      raise "DBTriggerGeneratorSqlite.place_expression_in_section? : Invalid accessor '#{accessor}' for operation '#{operation}'"
    end
  end

  # Decorate column expressions if needed
  # @param sql [String] SQL expression from Column_Expressions
  # @param operation [String] 'I', 'U', 'D', 'i'
  # @return [String] Decorated SQL expression
  def prepare_column_expressions(sql, operation)
    dup_sql = sql.dup                                                           # do not modify original
    if dup_sql.match(/^SELECT/i) or dup_sql.match(/^WITH/i)
      dup_sql = "(#{dup_sql})"                                                  # it is a SELECT statement, use subselect
    end
    if operation == 'i'
      dup_sql.gsub!(/(old|new)\./i, '')                                         # initialization of table data
    end
    "'||#{dup_sql}||'"
  end

  # called only if operation == 'I' and yn_initialization == 'Y'
  def create_load_sql(table)
    trigger_config    = @expected_triggers[table.name]['I']

    sql = "\
INSERT INTO Event_Logs(Table_ID, Operation, DBUser, Created_At, Payload, Msg_Key, Transaction_ID)
SELECT #{table.id}, 'i', 'main', strftime('%Y-%m-%d %H-%M-%f','now'), '\"new\": #{payload_json(table, trigger_config, nil, operation: 'i')}', #{message_key_sql(table, 'i')},
        #{table.yn_record_txid == 'Y' ? "'Dummy Tx-ID'" : "NULL" }
FROM   main.#{table.name}
"
    sql << "WHERE " if table.initialization_filter || trigger_config[:condition]
    sql << "(/* init filter */ #{table.initialization_filter})" if table.initialization_filter
    sql << "\nAND " if table.initialization_filter && trigger_config[:condition]
    sql << "(/* insert condition */ #{trigger_config[:condition].gsub(/new./i, '')})" if trigger_config[:condition]
    sql << "\nORDER BY #{table.initialization_order_by}" if table.initialization_order_by

    @load_sqls << { table_id: table.id, table_name: table.name, sql: sql }

    begin                                                                       # Check if table is readable
      table.raise_if_table_not_readable_by_movex_cdc
    rescue Exception => e
      @errors << {
        table_id:           table.id,
        table_name:         table.name,
        trigger_name:       self.build_trigger_name(table, 'I'),
        exception_class:    e.class.name,
        exception_message:  "Table #{table.schema.name}.#{table.name} is not readable by MOVEX CDC DB user! No initial data transfer executed! #{e.message}",
        sql:                sql
      }
    end
  end

  # Build SQL expression for message key
  def message_key_sql(table, operation)
    case table.kafka_key_handling
    when 'N' then 'NULL'
    when 'P' then primary_key_sql(table, operation)
    when 'F' then "'#{table.fixed_message_key}'"
    when 'T' then "'Dummy Tx-ID'"
    when 'E' then key_expression_sql(table, operation)
    else
      raise "Unsupported Kafka key handling type '#{table.kafka_key_handling}'"
    end
  end

  # get primary key columns sql for conversion to string
  def primary_key_sql(table, operation)

    pk_accessor =
      case operation
      when 'I' then 'new'
      when 'U' then 'new'
      when 'D' then 'old'
      when 'i' then nil                                                         # initialization of table data
      end

    pk_columns = Database.select_all("PRAGMA table_info(#{table.name})").select{|c| c.pk > 0}
    raise "DbTriggerSqlite.message_key_sql: Table #{table_name} does not have any primary key column" if pk_columns.length == 0

    result = "'{'||".dup
    result << pk_columns
                .map{|pkc| "'\"#{pkc['name']}\": '||#{convert_col({column_name: pkc['name'], type: pkc['type']}, pk_accessor)}" }
                .join("||','||")
    result << "||'}'"

    result
  end

  # get key expression sql for conversion to string
  # called only if table.kafka_key_handling == 'E'
  # @param table [Table] table object
  # @param operation [String] 'I', 'U', 'D'
  # @return [String] SQL expression
  def key_expression_sql(table, operation)
    expression = table.key_expression.dup
    expression.strip!
    case operation
    when 'I', 'U' then expression.gsub!(/old\./i, 'new.')
    when 'D' then expression.gsub!(/new\./i, 'old.')
    when 'i' then expression.gsub!(/(old|new)\./i, '')                            # initialization of table data
    end
    if expression.match(/^SELECT/i) or expression.match(/^WITH/i)               # it is a SELECT statement
      "(#{expression})"                                                         # Directly use susbselect in insert statement
    else
      expression
    end
  end

  def old_new_compare(columns)
    columns.map{|c|
      result = "old.#{c[:column_name]} != new.#{c[:column_name]}"
      if c[:notnull] == 0
        result << " OR (old.#{c[:column_name]} IS NULL AND new.#{c[:column_name]} IS NOT NULL)"
        result << " OR (old.#{c[:column_name]} IS NOT NULL AND new.#{c[:column_name]} IS NULL)"
      end
      result
    }.join(' OR ')
  end


  def exec_trigger_sql(sql, trigger_name, table)
    Rails.logger.info('DbTriggerGeneratorSqlite.exec_trigger_sql'){ "Execute trigger action: #{sql}" }
    ActiveRecord::Base.connection.execute(sql) unless  @dry_run
    @successes << {
      table_id:     table.id,
      table_name:   table.name,
      trigger_name: trigger_name,
      sql:          sql
    }
  rescue Exception => e
    ExceptionHelper.log_exception(e, 'DbTriggerSqlite.exec_trigger_sql', additional_msg: "Executing SQL\n#{sql}")
    @errors << {
      table_id:           table.id,
      table_name:         table.name,
      trigger_name:       trigger_name,
      exception_class:    e.class.name,
      exception_message:  e.message,
      sql:                sql
    }
  end

  def convert_col(column_hash, accessor)
    local_accessor = accessor.nil? ? '' : "#{accessor}."
    col_expr = "#{local_accessor}#{column_hash[:column_name]}"
    result = String.new
    result << "CASE WHEN #{col_expr} IS NULL THEN 'null' ELSE '\"'||#{col_expr}||'\"' END"        if column_hash[:type] == 'BLOB'
    result << "CASE WHEN #{col_expr} IS NULL THEN 'null' ELSE '\"'||#{col_expr}||'\"' END"        if column_hash[:type] =~ /datetime/i
    result << "CASE WHEN #{col_expr} IS NULL THEN 'null' ELSE #{col_expr} END"                    if column_hash[:type] =~ /number/i || column_hash[:type] =~ /int/i
    if column_hash[:type] =~ /char/i || column_hash[:type] =~ /text/i || column_hash[:type] =~ /varchar/i || column_hash[:type] =~ /clob/i
      result << "CASE WHEN #{col_expr} IS NULL THEN 'null' ELSE '\"'||REPLACE(#{col_expr}, '\"', '\\\"')||'\"' END"
    end
    raise "Unsupported data type '#{column_hash[:type]}'" if result.length == 0
    result
  end

  # generate trigger name, use public implementation
  def build_trigger_name(table, operation)
    DbTriggerGeneratorSqlite.build_trigger_name(table, operation)
  end

end
