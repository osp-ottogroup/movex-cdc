class TriggerOracle < TableLess
  # get ActiveRecord::Result with trigger records
  def self.find_all_by_schema_id(schema_id)
    schema = Schema.find schema_id
    select_all("\
      SELECT *
      FROM   All_Triggers
      WHERE  Owner = :owner
    ", {
        owner:        Trixx::Application.config.trixx_db_user,
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
        owner:          Trixx::Application.config.trixx_db_user,
        table_owner:    schema.name.upcase,
        table_name:     table.name.upcase,
        trigger_name:   trigger_name.upcase
    }
    )
  end

  # Generate triggers for schema
  def self.generate_db_triggers(schema_id, target_trigger_data)
    schema = Schema.find schema_id

    # get list of target triggers
    target_triggers = {}
    target_trigger_data.each do |tab|
      tab[:operations].each do |op|
        trigger_name = build_trigger_name(tab[:table_name], tab[:table_id], op[:operation])
        trigger_data = { trigger_name: trigger_name}
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
      if target_triggers.has_key? trigger.trigger_name                          # existing trigger should survive
        body = build_trigger_body(target_triggers[trigger.trigger_name])        # target body structure
        # TODO: Check trigger for difference on body and whenclause and replace if different

        target_triggers.delete trigger.trigger_name                             # remove processed trigger from target triggers at success and also at error
      else                                                                      # existing trigger is no more part of target structure
        sql = "DROP TRIGGER #{Trixx::Application.config.trixx_db_user}.#{trigger.trigger_name}"
        Rails.logger.info "Remove redundant trigger: #{sql}"
        ActiveRecord::Base.connection.execute sql
      end
    end

    # TODO: create remaining not yet existing triggers
    target_triggers.values.each do |target_trigger|
      body = build_trigger_body(target_trigger)
    end

  end

  private

  # generate trigger name from short operation (I/U/D) and table name
  def self.build_trigger_name(table_name, table_id, operation)
    middle_name = table_name
    middle_name = table_id.to_s if table_name.length > 21  # Ensure trigger name is less than 30 character
    "TRIXX_#{table_name.upcase}_#{operation == 'D' ? 'B' : 'A'}#{operation}"
  end

  # Build trigger code from hash
  def self.build_trigger_body(target_trigger_data)

  end
end