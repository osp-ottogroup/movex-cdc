class DbTriggerGeneratorSqlite < Database
  attr_reader :successes, :errors, :load_sqls

  TRIGGER_NAME_PREFIX = "TRIXX_"                                                # owner of trigger is always trixx_db_user, must not be part of trigger name

  ### class methods following

  # generate trigger name from short operation (I/U/D) and schema/table
  def self.build_trigger_name(schema_id, table_id, operation)
    "#{TRIGGER_NAME_PREFIX}#{operation}_#{schema_id}_#{table_id}"
  end

  # get ActiveRecord::Result with trigger records
  def self.find_all_by_schema_id(schema_id)
    select_all("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type = 'trigger'
    ")
  end

  def self.find_all_by_table(schema_id, table_id, schema_name, table_name)
    result = []
    select_all("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type     = 'trigger'
      AND    tbl_name = :table_name
    ", {table_name:   table_name}).each do |t|
      ['I', 'U', 'D'].each do |operation|                                       # check for I/U/D if trigger compares to TriXX trigger name
      if t['name'] == build_trigger_name(schema_id, table_id, operation)
        result << {
          operation:  operation,
          name:       t['name'],
          changed_at: nil
        }
      end
      end
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

  def initialize(schema_id:, user_options:, dry_run:)
    @schema       = Schema.find schema_id
    @user_options = user_options
    @dry_run      = dry_run
    @successes    = []                                                          # created triggers
    @errors       = []                                                          # errors during trigger creation
    @load_sqls    = []                                                          # PL/SQL snipped for initial load

    @existing_triggers = Database.select_all(
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
    @expected_triggers = {}
    expected_trigger_columns.each do |crec|

      unless @expected_triggers.has_key?(crec.table_name)
        @expected_triggers[crec.table_name] = {
          table_name:         crec.table_name
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
          }
        end
      end
    end

    # Add possible conditions at operation level
    expected_trigger_operation_filters.each do |cd|
      if @expected_triggers[cd.table_name] && @expected_triggers[cd.table_name][cd.operation]  # register filters only if operation has columns
        @expected_triggers[cd.table_name][cd.operation][:condition] = cd.filter
      end
    end
  end

  def generate_table_triggers(table_id:)
    table = Table.find table_id
    table_config    = @expected_triggers[table.name]

    ['I', 'U', 'D'].each do |operation|
      drop_obsolete_triggers(table, operation)

      unless table_config.nil?                                                  # at least one trigger expected for table
        trigger_config  = table_config[operation]
        unless trigger_config.nil?                                              # there should be a trigger for table/operation
          columns         = trigger_config[:columns]
          trigger_name    = build_trigger_name(table_id, operation)

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
            raise "Column #{trigger_column.column_name} does not exist in table #{@schema.name}.#{table.name}" if trigger_column[:type].nil?
          end

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
          create_load_sql(table, trigger_name) if operation == 'I' && table.yn_initialization == 'Y' # init table if requested regardless of whether trigger code has changed or not
        end
      end
    end
  rescue Exception => e                                                         # Ensure other tables are processed if error occurs at one table
    @errors << {
      table_id:           table.id,
      table_name:         table.name,
      trigger_name:       '[not specified]',
      exception_class:    e.class.name,
      exception_message:  e.message,
      sql:                '[not specified]'
    }
  end

  private

  def drop_obsolete_triggers(table, operation)
    @existing_triggers.select{|t|
      t.table_name == table.name && t.operation == operation
    }.each do |t|
      if !@expected_triggers.has_key?(table.name) || !@expected_triggers[table.name].has_key?(operation)
        Rails.logger.debug("drop_obsolete_triggers: Existing trigger  #{table.name}.#{t.trigger_name} not expected in config, drop to remove")
        exec_trigger_sql("DROP TRIGGER #{t.trigger_name}", t.trigger_name, table)       # Remove existing trigger
      else
        Rails.logger.debug("drop_obsolete_triggers: Existing trigger #{table.name}.#{t.trigger_name} expected in config, not dropped")
      end
    end
  end

  def build_trigger_header(table, operation)
    table_config    = @expected_triggers[table.name]
    trigger_config  = table_config[operation]
    trigger_name = build_trigger_name(table.id, operation)

    result = "CREATE TRIGGER #{trigger_name} #{long_operation_from_short(operation)}"
    result << " ON #{table.name} FOR EACH ROW"
    result << " WHEN " if trigger_config[:condition] || operation == 'U'
    result << " (#{trigger_config[:condition]})" if trigger_config[:condition]
    result << " AND " if trigger_config[:condition] && operation == 'U'
    result << " (#{old_new_compare(trigger_config[:columns])}) " if operation == 'U'
    result
  end

  # Build trigger code from hash
  def build_trigger_body(table, operation)
    table_config    = @expected_triggers[table.name]
    trigger_config  = table_config[operation]

    accessors =
      case operation
      when 'I' then ['new']
      when 'U' then ['old', 'new']
      when 'D' then ['old']
      end

    payload = ''
    accessors.each do |accessor|
      payload << "\"#{accessor}\": #{payload_json(trigger_config, accessor)}"
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

  def payload_json(trigger_config, accessor)
    json = "{"
    json << trigger_config[:columns].map{|c| "\"#{c[:column_name]}\": '||#{convert_col(c, accessor)}||'"}.join(",\n")
    json << "}"
    json
  end

  # called only if operation == 'I' and yn_initialization == 'Y'
  def create_load_sql(table, trigger_name)
    trigger_config    = @expected_triggers[table.name]['I']

    sql = "\
INSERT INTO Event_Logs(Table_ID, Operation, DBUser, Created_At, Payload, Msg_Key, Transaction_ID)
SELECT #{table.id}, 'I', 'main', strftime('%Y-%m-%d %H-%M-%f','now'), '\"new\": #{payload_json(trigger_config, nil)}', #{message_key_sql(table, 'N')},
        #{table.yn_record_txid == 'Y' ? "'Dummy Tx-ID'" : "NULL" }
FROM   main.#{table.name}
"
    sql << "WHERE " if table.initialization_filter || trigger_config[:condition]
    sql << "(/* init filter */ #{table.initialization_filter})" if table.initialization_filter
    sql << " AND " if table.initialization_filter && trigger_config[:condition]
    sql << "(/* insert condition */ #{trigger_config[:condition].gsub(/new./i, '')})" if trigger_config[:condition]

    @load_sqls << { table_id: table.id, table_name: table.name, sql: sql }

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

  # Build SQL expression for message key
  def message_key_sql(table, operation)
    case table.kafka_key_handling
    when 'N' then 'NULL'
    when 'P' then primary_key_sql(table, operation)
    when 'F' then "'#{table.fixed_message_key}'"
    when 'T' then "'Dummy Tx-ID'"
    else
      raise "Unsupported Kafka key handling type '#{table.kafka_key_handling}'"
    end
  end

  # get primary key columns sql for conversion to string
  def primary_key_sql(table, operation)

    pk_accessor =
      case operation
      when 'I' then 'new.'
      when 'U' then 'new.'
      when 'D' then 'old.'
      when 'N' then ''                                                          # initialization of table data
      end

    pk_columns = Database.select_all("PRAGMA table_info(#{table.name})").select{|c| c.pk > 0}
    raise "DbTriggerSqlite.message_key_sql: Table #{table_name} does not have any primary key column" if pk_columns.length == 0

    result = "'{' ||"
    result << pk_columns.map {|pkc|
      # TODO: put quotes on string and date
      "'#{pkc.name}: '|| #{pk_accessor}#{pkc.name}"
    }.join("||','||")
    result << "|| ' }'"
    result
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
    Rails.logger.info "Execute trigger action: #{sql}"
    ActiveRecord::Base.connection.execute(sql) unless  @dry_run
    @successes << {
      table_id:     table.id,
      table_name:   table.name,
      trigger_name: trigger_name,
      sql:          sql
    }
  rescue Exception => e
    ExceptionHelper.log_exception(e, "DbTriggerSqlite.exec_trigger_sql: Executing SQL\n#{sql}")
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
    result = ''
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
  def build_trigger_name(table_id, operation)
    DbTriggerGeneratorSqlite.build_trigger_name(@schema.id, table_id, operation)
  end

  def long_operation_from_short(operation)
    case operation
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    end
  end


end
