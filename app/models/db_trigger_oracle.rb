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

  def self.find_by_table_id_and_trigger_name(table_id, trigger_name)
    table  = Table.find table_id
    schema = Schema.find table.schema_id
    select_one("\
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
  # Return:     Array of trigger-specific errors (successful if array is empty)
  def self.generate_db_triggers(schema_id, target_trigger_data)
    trigger_errors = []
    schema = Schema.find schema_id

    # get list of target triggers
    target_triggers = {}
    target_trigger_data.each do |tab|
      tab[:operations].each do |op|
        trigger_name = build_trigger_name(tab[:table_name], tab[:table_id], op[:operation])
        trigger_data = {
            schema_name:    schema.name,
            table_name:     tab[:table_name],
            trigger_name:   trigger_name,
            operation:      operation_from_short_op(op[:operation]),            # INSERT/UPDATE/DELETE
            condition:      op[:condition],
            columns:        op[:columns]
        }

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
            table_owner:  schema.name.upcase
        }
    )

    # Remove trigger that are no more part of target structure
    existing_triggers.each do |trigger|                                         # iterate over existing trigger of target schema
      trigger_name = trigger['trigger_name']                                    # Name of existing trigger
      if target_triggers.has_key? trigger_name                                  # existing trigger should survive
        body = build_trigger_body(target_triggers[trigger_name])                # target body structure
        # TODO: Check trigger for difference on body and whenclause and replace if different

        exec_trigger_sql "REPLACE #{build_trigger_header(target_triggers[trigger_name])}\n#{body}", trigger_errors
        target_triggers.delete trigger_name                                     # remove processed trigger from target triggers at success and also at error
      else                                                                      # existing trigger is no more part of target structure
        exec_trigger_sql "DROP TRIGGER #{Trixx::Application.config.trixx_db_user}.#{trigger_name}", trigger_errors
      end
    end

    # TODO: create remaining not yet existing triggers
    target_triggers.values.each do |target_trigger|
      exec_trigger_sql "CREATE #{build_trigger_header(target_trigger)}\n#{build_trigger_body(target_trigger)}", trigger_errors
    end
    trigger_errors                                                              # return array if trigger-specific errors (successful if array is empty)
  end

  private

  # generate trigger name from short operation (I/U/D) and table name
  def self.build_trigger_name(table_name, table_id, operation)
    middle_name = table_name
    middle_name = table_id.to_s if table_name.length > 22  # Ensure trigger name is less than 30 character
    "TRIXX_#{table_name.upcase}_#{operation}"
  end

  # Build trigger header from hash
  def self.build_trigger_header(target_trigger_data)
    "CREATE OR REPLACE TRIGGER #{Trixx::Application.config.trixx_db_user}.#{target_trigger_data[:trigger_name]} \
FOR #{target_trigger_data[:operation]} \
OF #{target_trigger_data[:columns].map{|x| x[:column_name]}.join(',')} \
ON #{target_trigger_data[:schema_name]}.#{target_trigger_data[:table_name]}"
  end

  # Build trigger code from hash
  def self.build_trigger_body(target_trigger_data)

  end

  def self.operation_from_short_op(short_op)
    case short_op
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    else raise "Unknown short operation '#{short_op}'"
    end
  end

  def self.exec_trigger_sql(sql, trigger_errors)
    Rails.logger.info "Execute trigger action: #{sql}"
    ActiveRecord::Base.connection.execute(sql)
  rescue Exception => e
    trigger_errors << {
        exception_class:    e.class.name,
        exception_message:  e.message,
        sql:                sql
    }
  end

end