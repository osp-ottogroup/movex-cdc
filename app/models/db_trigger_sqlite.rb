class DbTriggerSqlite < TableLess

  # get ActiveRecord::Result with trigger records
  def self.find_all_by_schema_id(schema_id)
    select_all("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type = 'trigger'
    ")
  end

  def self.find_by_table_id_and_trigger_name(table_id, trigger_name)
    select_first_row("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type = 'trigger'
    ")
    # TODO: Filter on table and trigger
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
      tab[:operations].each do |op|
        trigger_name = build_trigger_name(tab[:table_name], tab[:table_id], op[:operation])
        trigger_data = {
            schema_name:      @schema.name,
            table_id:         tab[:table_id],
            table_name:       tab[:table_name],
            trigger_name:     trigger_name,
            operation:        operation_from_short_op(op[:operation]),          # INSERT/UPDATE/DELETE
            operation_short:  op[:operation],                                   # I/U/D
            condition:        op[:condition],
            columns:          op[:columns]
        }

        target_triggers[trigger_name] = trigger_data                            # add single trigger data to hash of all triggers
      end
    end

    existing_triggers = TableLess.select_all(
        "SELECT Name Trigger_Name, Tbl_Name Table_Name, SQL
         FROM   SQLite_Master
         WHERE  Type       = 'trigger'
        "
    )

    # Remove trigger that are no more part of target structure
    existing_triggers.each do |trigger|                                         # iterate over existing trigger of target schema
      trigger_name = trigger['Trigger_Name']                                    # Name of existing trigger
      if trigger_name['TRIXX']                                                  # trigger generated by trixx
        if target_triggers.has_key? trigger_name                                # existing trigger should survive
          create_sql = "#{build_trigger_header(target_triggers[trigger_name])}\n#{build_trigger_body(target_triggers[trigger_name]) }"
          if create_sql != trigger[:sql]                                          # Trigger code has changed
            exec_trigger_sql "DROP TRIGGER #{trigger_name}", trigger_name       # Remove existing trigger
            exec_trigger_sql create_sql, trigger_name                           # create trigger again
          end
          target_triggers.delete trigger_name                                   # remove processed trigger from target triggers at success and also at error
        else                                                                    # existing trigger is no more part of target structure
          exec_trigger_sql "DROP TRIGGER #{trigger_name}", trigger_name
        end
      end
    end

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
  def build_trigger_name(table_name, table_id, operation)
    middle_name = table_name
    middle_name = table_id.to_s if table_name.length > 22  # Ensure trigger name is less than 30 character
    "TRIXX_#{table_name.upcase}_#{operation}"
  end

  # Build trigger header from hash
  def build_trigger_header(target_trigger_data)
    result = "CREATE TRIGGER #{Trixx::Application.config.trixx_db_user}.#{target_trigger_data[:trigger_name]} #{target_trigger_data[:operation]}"
    result << " ON #{target_trigger_data[:table_name]} FOR EACH ROW"
    result << " WHEN #{target_trigger_data[:condition]}" if target_trigger_data[:condition]
    result
  end

  # Build trigger code from hash
  def build_trigger_body(target_trigger_data)
    accessors =
        case target_trigger_data[:operation]
        when 'INSERT' then ['new']
        when 'UPDATE' then ['old', 'new']
        when 'DELETE' then ['old']
        end
    payload = ''
    accessors.each do |accessor|
      payload << "#{accessor}: {"
      payload << target_trigger_data[:columns].map{|c| "#{c[:column_name]}: '||ifnull(#{accessor}.#{c[:column_name]}, '')||'"}.join(",\n")
      payload << "}"
    end

    "\
BEGIN
  INSERT INTO Event_Logs(Table_ID, Operation, DBUser, Created_At, Payload) VALUES (#{target_trigger_data[:table_id]}, '#{target_trigger_data[:operation_short]}', 'main', strftime('%Y-%m-%d %H-%M-%f','now'), '#{payload}');
END;"
  end

  def operation_from_short_op(short_op)
    case short_op
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    else raise "Unknown short operation '#{short_op}'"
    end
  end

  def exec_trigger_sql(sql, trigger_name)
    Rails.logger.info "Execute trigger action: #{sql}"
    ActiveRecord::Base.connection.execute(sql)
    @trigger_successes << {
        trigger_name: trigger_name,
        sql:          sql
    }
  rescue Exception => e
    ExceptionHelper.log_exception(e, "DbTriggerSqlite.exec_trigger_sql: Executing SQL\n#{sql}")
    @trigger_errors << {
        trigger_name:       trigger_name,
        exception_class:    e.class.name,
        exception_message:  e.message,
        sql:                sql
    }
  end

end