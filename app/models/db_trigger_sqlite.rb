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
    select_one("\
      SELECT *
      FROM   SQLite_Master
      WHERE  Type = 'trigger'
    ")
    # TODO: Filter on table and trigger
  end

  # Generate triggers for schema
  def self.generate_db_triggers(schema_id, target_trigger_data)
    # TODO: Implement
  end

end