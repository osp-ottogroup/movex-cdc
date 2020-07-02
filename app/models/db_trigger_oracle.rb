class DbTriggerOracle < Database
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

  # Generate all requested triggers for schema
  # Parameter:  schema_id:            ID of schema in Table Schemas
  #             target_trigger_data:  Array of hashes with trigger data for single table
  # Return:     Hash with Arrays of trigger-specific successes and trigger-specific errors
  def self.generate_db_triggers(schema_id, target_trigger_data)
    self.new(schema_id, target_trigger_data).generate_db_triggers_internal
  end

  def initialize(schema_id, target_trigger_data)
    @schema               = Schema.find schema_id
    @target_trigger_data  = target_trigger_data
    @trigger_errors       = []
    @trigger_successes    = []
  end

  def generate_db_triggers_internal
    # get list of target triggers
    target_triggers = {}
    @target_trigger_data.each do |tab|
      ora_columns = {}                                                          # list of table columns from db with column_name as key
      Database.select_all(
          "SELECT Column_Name, Data_Type, Nullable FROM DBA_Tab_Columns WHERE Owner = :owner AND Table_Name = :table_name",
          { owner: @schema.name, table_name: tab[:table_name]}
      ).each do |c|
        ora_columns[c['column_name']] = {
            data_type: c['data_type'],
            nullable:  c['nullable']
        }
      end

      tab[:operations].each do |op|
        trigger_name = DbTriggerOracle.build_trigger_name(@schema.id, tab[:table_id], op[:operation])
        trigger_data = {
            schema_id:          @schema.id,
            schema_name:        @schema.name,
            table_id:           tab[:table_id],
            table_name:         tab[:table_name],
            trigger_name:       trigger_name,
            operation:          KeyHelper.operation_from_short_op(op[:operation]),          # INSERT/UPDATE/DELETE
            operation_short:    op[:operation],                                   # I/U/D
            kafka_key_handling: tab[:kafka_key_handling],
            fixed_message_key:  tab[:fixed_message_key],
            condition:          op[:condition],
            columns:            op[:columns]
        }

        trigger_data[:columns].each do |c|
          raise "Column '#{c[:column_name]}' does not exists in DB for table '#{@schema.name}.#{tab[:table_name]}'" if !ora_columns.has_key?(c[:column_name])
          c[:data_type] = ora_columns[c[:column_name]]&.fetch(:data_type)
          c[:nullable]  = ora_columns[c[:column_name]]&.fetch(:nullable)
        end

        target_triggers[trigger_name] = trigger_data                            # add single trigger data to hash of all triggers
      end
    end

    existing_triggers = Database.select_all(
        "SELECT Table_Name, Trigger_Name, Description, Trigger_Body
         FROM   All_Triggers
         WHERE  Owner       = :owner
         AND    Table_Owner = :table_owner
         AND    Trigger_Name LIKE :prefix ||'%'
        ",
        {
            owner:        Trixx::Application.config.trixx_db_user,
            table_owner:  @schema.name,
            prefix:       DbTriggerOracle.trigger_name_prefix
        }
    )

    # Check trigger for removal or replacement
    existing_triggers.each do |trigger|                                         # iterate over existing trigger of target schema
      trigger_name = trigger['trigger_name']                                    # Name of existing trigger
      if target_triggers.has_key?(trigger_name)                                 # existing trigger should survive
        target_trigger_data = target_triggers[trigger_name]
        body = build_trigger_body(target_trigger_data)                          # target body structure

        if trigger['trigger_body']                != body ||
            trigger['description'].gsub("\n", '') != build_trigger_description(target_trigger_data)
          exec_trigger_sql "#{build_trigger_header(target_triggers[trigger_name])}\n#{body}", trigger_name  # replace existing trigger
        else
          Rails.logger.debug "DbTriggerOracle.generate_db_triggers_internal: Trigger #{@schema.name}.#{trigger_name} not replaced because nothing hs changed"
        end

        target_triggers.delete trigger_name                                     # remove processed trigger from target triggers at success and also at error
      else                                                                      # existing trigger is no more part of target structure
        exec_trigger_sql "DROP TRIGGER #{Trixx::Application.config.trixx_db_user}.#{trigger_name}", trigger_name
      end
    end

    # create remaining not yet existing triggers
    target_triggers.values.each do |target_trigger|
      exec_trigger_sql "#{build_trigger_header(target_trigger)}\n#{build_trigger_body(target_trigger)}", target_trigger[:trigger_name]
    end

    # return an hash with arrays
    {
        successes: @trigger_successes,
        errors:    @trigger_errors
    }
  end

  private
  @@trigger_name_prefix = nil
  def self.trigger_name_prefix
    if @@trigger_name_prefix.nil?
      @@trigger_name_prefix = "TRIXX_"                                          # owner of trigger is always trixx_db_user, must not be part of trigger name
    end
    @@trigger_name_prefix
  end

  # generate trigger name from short operation (I/U/D) and table name
  # Trigger name consists of TRIXX_<Hash over trixx owner>_<operation>_<Hash over table name>
  def self.build_trigger_name(schema_id, table_id, operation)
    "#{trigger_name_prefix}#{operation}_#{schema_id}_#{table_id}"
  end

  # Build SQL expression for message key
  def message_key_sql(target_trigger_data)
    case target_trigger_data[:kafka_key_handling]
    when 'N' then 'NULL'
    when 'P' then primary_key_sql(target_trigger_data[:schema_name], target_trigger_data[:table_name], target_trigger_data[:operation])
    when 'F' then "'#{target_trigger_data[:fixed_message_key]}'"
    else
      raise "Unsupported Kafka key handling type '#{target_trigger_data[:kafka_key_handling]}'"
    end
  end

  # get primary key columns sql for conversion to string
  def primary_key_sql(schema_name, table_name, operation)

    pk_accessor =
        case operation
        when 'INSERT' then 'new'
        when 'UPDATE' then 'new'
        when 'DELETE' then 'old'
        end

    result = "'{'"
    first = true
    pk_constraint_name = Database.select_one("SELECT Constraint_Name
                                               FROM   DBA_Constraints
                                               WHERE  Owner       = :schema_name
                                               AND    Table_Name  = :table_name
                                               AND    Constraint_Type = 'P'
                                              ",
                                             schema_name:  schema_name,
                                             table_name:   table_name
    )
    raise "DbTriggerOracle.message_key_sql: Table #{schema_name}.#{table_name} does not have a primary key" if pk_constraint_name.nil?

    Database.select_all("SELECT cc.column_name, tc.Data_Type
                          FROM   DBA_Cons_Columns cc
                          JOIN   DBA_Tab_Columns tc ON tc.Owner = cc.Owner AND tc.Table_name = cc.Table_Name AND tc.Column_Name = cc.Column_Name
                          WHERE  cc.Owner           = :schema_name
                          AND    cc.Table_Name      = :table_name
                          AND    cc.Constraint_Name = :constraint_name
                          ORDER BY cc.Position
                         ",
                        schema_name:     schema_name,
                        table_name:      table_name,
                        constraint_name: pk_constraint_name
    ).each do |i|
      result << "||'#{',' unless first} #{i['column_name']}: '||#{convert_col({column_name: i['column_name'] , data_type: i['data_type']}, pk_accessor)}"
      first = false
    end
    result << " || ' }'"
    result
  end

  def build_trigger_description(target_trigger_data)
    result = "#{Trixx::Application.config.trixx_db_user}.#{target_trigger_data[:trigger_name]} FOR #{target_trigger_data[:operation]}"
    result << " OF #{target_trigger_data[:columns].map{|x| x[:column_name]}.join(',')}" if target_trigger_data[:operation] == 'UPDATE'
    result << " ON #{target_trigger_data[:schema_name]}.#{target_trigger_data[:table_name]}"
    result
  end

  # Build trigger header from hash
  def build_trigger_header(target_trigger_data)
    "CREATE OR REPLACE TRIGGER #{build_trigger_description(target_trigger_data)}"
  end

  # Build trigger code from hash
  def build_trigger_body(target_trigger_data)
    condition_indent = target_trigger_data[:condition] ? '  ' : ''              # Number of chars for row indent
    update_indent    = target_trigger_data[:operation] == 'UPDATE' ? '  ' : ''

    "\
COMPOUND TRIGGER
TYPE Payload_Rec_Type IS RECORD (
  Payload CLOB,
  Msg_Key VARCHAR2(4000)
);
TYPE Payload_Tab_Type IS TABLE OF Payload_Rec_Type INDEX BY PLS_INTEGER;
payload_rec Payload_Rec_Type;
payload_tab Payload_Tab_Type;
tab_size    PLS_INTEGER;
dbuser      VARCHAR2(128) := USER;

PROCEDURE Flush IS
BEGIN
  FORALL i IN 1..payload_tab.COUNT
    INSERT INTO #{Trixx::Application.config.trixx_db_user}.Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Created_At, Msg_Key)
    VALUES (Event_Logs_Seq.NextVal, #{target_trigger_data[:table_id]}, '#{target_trigger_data[:operation_short]}', dbuser, payload_tab(i).Payload, SYSTIMESTAMP, payload_tab(i).msg_key);
  payload_tab.DELETE;
END Flush;

BEFORE STATEMENT IS
BEGIN
  payload_tab.DELETE; /* remove possible fragments of previous transactions */
END BEFORE STATEMENT;

#{position_from_operation(target_trigger_data[:operation])} EACH ROW IS
BEGIN
  tab_size := Payload_Tab.COUNT;
  IF tab_size > 1000 THEN
    Flush;
    tab_size := 0;
  END IF;

  #{"IF #{target_trigger_data[:condition]} THEN" if target_trigger_data[:condition]}
  #{"#{condition_indent}IF #{old_new_compare(target_trigger_data[:columns])} THEN" if target_trigger_data[:operation] == 'UPDATE'}
  #{condition_indent}#{update_indent}payload_rec.payload := #{payload_command(target_trigger_data)};
  #{condition_indent}#{update_indent}payload_rec.msg_key := #{message_key_sql(target_trigger_data)};
  #{condition_indent}#{update_indent}payload_tab(tab_size + 1) := payload_rec;
  #{"#{condition_indent}END IF;" if target_trigger_data[:operation] == 'UPDATE'}
  #{"END IF;" if target_trigger_data[:condition]}

END #{position_from_operation(target_trigger_data[:operation])} EACH ROW;

AFTER STATEMENT IS
BEGIN
  Flush;
END AFTER STATEMENT;

END #{target_trigger_data[:trigger_name]};
"
  end

  def position_from_operation(operation)
    return 'BEFORE' if operation == 'DELETE'
    'AFTER'
  end

  # compare old and new values for update trigger
  def old_new_compare(columns)
    columns.map{|c|
      result = ":old.#{c[:column_name]} != :new.#{c[:column_name]}"
      if c[:nullable] == 'Y'
        result << " OR (:old.#{c[:column_name]} IS NULL AND :new.#{c[:column_name]} IS NOT NULL)"
        result << " OR (:old.#{c[:column_name]} IS NOT NULL AND :new.#{c[:column_name]} IS NULL)"
      end
      result
    }.join(' OR ')
  end

  def exec_trigger_sql(sql, trigger_name)
    Rails.logger.info "Execute trigger action: #{sql}"
    ActiveRecord::Base.connection.execute(sql)
    errors = Database.select_all(
        "SELECT * FROM All_Errors WHERE Owner = :owner AND Name = :name ORDER BY Sequence",
        {
            owner:  Trixx::Application.config.trixx_db_user,
            name:   trigger_name
        }
    )
    if errors.count == 0
      @trigger_successes << {
          trigger_name: trigger_name,
          sql:          sql
      }
    else
      errors.each do |error|
        @trigger_errors << {
            trigger_name:       trigger_name,
            exception_class:    "Compile error line #{error['line']} position #{error['position']}",
            exception_message:  error['text'],
            sql:                sql
        }
      end
    end


  rescue Exception => e
    ExceptionHelper.log_exception(e, "DbTriggerOracle.exec_trigger_sql: Executing SQL:\n#{sql}")
    @trigger_errors << {
        trigger_name:       trigger_name,
        exception_class:    e.class.name,
        exception_message:  e.message,
        sql:                sql
    }
  end

  # generate concatenated PL/SQL-commands for payload
  def payload_command(target_trigger_data)
    case target_trigger_data[:operation]
    when 'INSERT' then payload_command_internal(target_trigger_data, 'new')
    when 'UPDATE' then "#{payload_command_internal(target_trigger_data, 'old')}||',\n'||#{payload_command_internal(target_trigger_data, 'new')}"
    when 'DELETE' then payload_command_internal(target_trigger_data, 'old')
    else
      raise "Unknown operation #{target_trigger_data[:operation]}"
    end
  end

  def payload_command_internal(target_trigger_data, old_new)
    result = "'\"#{old_new}\": {\n'"
    target_trigger_data[:columns].each_index do |i|
      col = target_trigger_data[:columns][i]
      result << "||'  \"#{col[:column_name]}\": '||#{convert_col(col, old_new)}||'#{',' if i < target_trigger_data[:columns].count-1}\n'"
    end
    result << "||'}'"
    result
  end

  # convert values to string in PL/SQL
  def convert_col(column_hash, old_new)
    accessor = ":#{old_new}"
    result = ''
    result << "CASE WHEN #{accessor}.#{column_hash[:column_name]} IS NULL THEN 'NULL' ELSE " if column_hash[:nullable] == 'Y'
    result << case column_hash[:data_type]
    when 'CHAR', 'CLOB', 'NCHAR', 'NCLOB', 'NVARCHAR2', 'LONG', 'ROWID', 'UROWID', 'VARCHAR2'   # character data types
    then "'\"'||REPLACE(#{accessor}.#{column_hash[:column_name]}, '\"', '\\\"')||'\"'"           # place between double quotes "xxx" and escape double quote to \"
    when 'BINARY_DOUBLE', 'BINARY_FLOAT', 'FLOAT', 'NUMBER'                                                      # Numeric data types
    then "TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'TM','NLS_NUMERIC_CHARACTERS=''.,''')"
    when 'DATE'                         then "''''||TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'YYYY-MM-DD\"T\"HH24:MI:SS')||''''"
    when 'RAW'                          then "''''||RAWTOHEX(#{accessor}.#{column_hash[:column_name]})||''''"
    when /^TIMESTAMP\([0-9]\)$/
    then "'\"'||TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFF')||'\"'"
    when /^TIMESTAMP\([0-9]\) WITH .*TIME ZONE$/
    then "'\"'||TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFFTZR')||'\"'"
    else
      raise "Unsupported column type '#{column_hash[:data_type]}' for column '#{column_hash[:column_name]}'"
    end
    result << " END" if column_hash[:nullable] == 'Y'
    result
  end

end