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
  def self.generate_triggers(schema_id)
    # TODO: Implement
    target_trigger_data = {}                                                    # Hash with target trigger states for schema
    Tables.where(schema_id: schema_id).each do |table|
      ['I', 'U', 'D'].each do |operation|

      end
    end

  end

  private


end