class DbTriggerOracle < TableLess
  # get ActiveRecord::Result with trigger records
  def self.find_all_by_schema_id(schema_id)
    schema = Schema.find schema_id
    select_all("\
      SELECT *
      FROM   All_Triggers
      WHERE  Owner        = :owner
      AND    Table_Owner  = :table_owner
    ", {
        owner:        Trixx::Application.config.trixx_db_user.upcase,
        table_owner:  schema.name.upcase
    }
    )
  end

  # get Array of Hash with trigger info
  def self.find_all_by_table(table_id, schema_name, table_name)
    result = []
    select_all("\
      SELECT t.Trigger_name, o.Last_DDL_Time
      FROM   All_Triggers t
      JOIN   All_Objects o ON o.Owner = t.Owner AND o.Object_Name = t.Trigger_Name AND o.Object_Type = 'TRIGGER'
      WHERE  t.Owner        = :owner
      AND    t.Table_Owner  = :table_owner
      AND    t.Table_Name   = :table_name
    ", {
        owner:        Trixx::Application.config.trixx_db_user.upcase,
        table_owner:  schema_name.upcase,
        table_name:   table_name.upcase
    }).each do |t|
      ['I', 'U', 'D'].each do |operation|                                       # check for I/U/D if trigger compares to TriXX trigger name
        if t['trigger_name'] == build_trigger_name(table_name, table_id, operation)
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
        owner:          Trixx::Application.config.trixx_db_user.upcase,
        table_owner:    schema.name.upcase,
        table_name:     table.name.upcase,
        trigger_name:   trigger_name.upcase
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
      TableLess.select_all(
          "SELECT Column_Name, Data_Type FROM DBA_Tab_Columns WHERE Owner = :owner AND Table_Name = :table_name",
          { owner: @schema.name, table_name: tab[:table_name]}
      ).each do |c|
        ora_columns[c['column_name']] = {
            data_type: c['data_type']
        }
      end

      tab[:operations].each do |op|
        trigger_name = build_trigger_name(tab[:table_name], tab[:table_id], op[:operation])
        trigger_data = {
            schema_id:        @schema.id,
            schema_name:      @schema.name,
            table_id:         tab[:table_id],
            table_name:       tab[:table_name],
            trigger_name:     trigger_name,
            operation:        operation_from_short_op(op[:operation]),          # INSERT/UPDATE/DELETE
            operation_short:  op[:operation],                                   # I/U/D
            condition:        op[:condition],
            columns:          op[:columns]
        }

        trigger_data[:columns].each do |c|
          raise "Column '#{c[:column_name]}' does not exists in DB for table '#{@schema.name}.#{tab[:table_name]}'" if !ora_columns.has_key?(c[:column_name])
          c[:data_type] = ora_columns[c[:column_name]]&.fetch(:data_type)
        end


        target_triggers[trigger_name] = trigger_data                            # add single trigger data to hash of all triggers
      end
    end

    existing_triggers = TableLess.select_all(
        "SELECT Trigger_Name, When_Clause, Trigger_Body
         FROM   All_Triggers
         WHERE  Owner       = :owner
         AND    Table_Owner = :table_owner
         AND    Trigger_Name LIKE 'TRIXX%'
        ",
        {
            owner:        Trixx::Application.config.trixx_db_user.upcase,
            table_owner:  @schema.name.upcase
        }
    )

    # Remove trigger that are no more part of target structure
    existing_triggers.each do |trigger|                                         # iterate over existing trigger of target schema
      trigger_name = trigger['trigger_name']                                    # Name of existing trigger
      if target_triggers.has_key? trigger_name                                  # existing trigger should survive
        body = build_trigger_body(target_triggers[trigger_name])                # target body structure
        # TODO: Check trigger for difference on body and whenclause and replace only if different

        exec_trigger_sql "#{build_trigger_header(target_triggers[trigger_name])}\n#{body}", trigger_name
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

  # generate trigger name from short operation (I/U/D) and table name
  def self.build_trigger_name(table_name, table_id, operation)
    middle_name = table_name
    middle_name = table_id.to_s if table_name.length > 22  # Ensure trigger name is less than 30 character
    "TRIXX_#{table_name.upcase}_#{operation}"
  end

  # Build trigger header from hash
  def build_trigger_header(target_trigger_data)
    result = "CREATE OR REPLACE TRIGGER #{Trixx::Application.config.trixx_db_user}.#{target_trigger_data[:trigger_name]} FOR #{target_trigger_data[:operation]}"
    result << " OF #{target_trigger_data[:columns].map{|x| x[:column_name]}.join(',')}" if target_trigger_data[:operation] == 'UPDATE'
    result << " ON #{target_trigger_data[:schema_name]}.#{target_trigger_data[:table_name]}"
    result
  end

  # Build trigger code from hash
  def build_trigger_body(target_trigger_data)
    "\
COMPOUND TRIGGER

TYPE Payload_Tab_Type IS TABLE OF CLOB INDEX BY PLS_INTEGER;
payload_tab Payload_Tab_Type;
tab_size    PLS_INTEGER;
dbuser      VARCHAR2(128) := USER;

PROCEDURE Flush IS
BEGIN
  FORALL i IN 1..payload_tab.COUNT
    INSERT INTO Event_Logs(ID, Table_ID, Operation, DBUser, Payload, Created_At)
    VALUES (Event_Logs_Seq.NextVal, #{target_trigger_data[:table_id]}, '#{target_trigger_data[:operation_short]}', dbuser, payload_tab(i), SYSTIMESTAMP);
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
  #{"  " if target_trigger_data[:condition]}payload_tab(tab_size + 1) := #{payload_command(target_trigger_data)};
  #{"END IF;" if target_trigger_data[:condition]}
END #{position_from_operation(target_trigger_data[:operation])} EACH ROW;

AFTER STATEMENT IS
BEGIN
  Flush;
END AFTER STATEMENT;

END #{target_trigger_data[:trigger_name]};
"
  end

  def operation_from_short_op(short_op)
    case short_op
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    else raise "Unknown short operation '#{short_op}'"
    end
  end

  def position_from_operation(operation)
    return 'BEFORE' if operation == 'DELETE'
    'AFTER'
  end

  def exec_trigger_sql(sql, trigger_name)
    Rails.logger.info "Execute trigger action: #{sql}"
    ActiveRecord::Base.connection.execute(sql)
    errors = TableLess.select_all(
        "SELECT * FROM All_Errors WHERE Owner = :owner AND Name = :name ORDER BY Sequence",
        {
            owner:  Trixx::Application.config.trixx_db_user.upcase,
            name:   trigger_name.upcase
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
    result = "'#{old_new}: {\n'"
    target_trigger_data[:columns].each_index do |i|
      col = target_trigger_data[:columns][i]
      result << "||'  #{col[:column_name]}: '||#{convert_col(target_trigger_data, col, old_new)}||'#{',' if i < target_trigger_data[:columns].count-1}\n'"
    end
    result << "||'}'"
    result
  end

  # convert values to string in PL/SQL
  def convert_col(target_trigger_data, column_hash, old_new)
    accessor = ":#{old_new}"

    case column_hash[:data_type]

    when 'CHAR', 'CLOB', 'NCHAR', 'NCLOB', 'NVARCHAR2', 'LONG', 'ROWID', 'UROWID', 'VARCHAR2'    # character data types
    then "''''||#{accessor}.#{column_hash[:column_name]}||''''"
    when 'BINARY_DOUBLE', 'BINARY_FLOAT', 'FLOAT', 'NUMBER'                                                      # Numeric data types
    then "TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'TM','NLS_NUMERIC_CHARACTERS=''.,''')"
    when 'DATE'                         then "''''||TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'YYYY-MM-DD\"T\"HH24:MI:SS')||''''"
    when 'RAW'                          then "''''||RAWTOHEX(#{accessor}.#{column_hash[:column_name]})||''''"
    when /^TIMESTAMP\([0-9]\)$/
    then "''''||TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFF')||''''"
    when /^TIMESTAMP\([0-9]\) WITH .*TIME ZONE$/
    then "''''||TO_CHAR(#{accessor}.#{column_hash[:column_name]}, 'YYYY-MM-DD\"T\"HH24:MI:SSxFFTZR')||''''"
    else
      raise "Unsupported column type '#{column_hash[:data_type]}' for column '#{column_hash[:column_name]}'"
    end
  end
end