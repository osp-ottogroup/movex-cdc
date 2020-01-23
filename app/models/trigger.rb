class Trigger

  # delegate method calls to DB-specific implementation classes
  METHODS_TO_DELEGATE = [
      :find_all_by_schema_id,
      :find_by_table_id_and_trigger_name,
      :generate_triggers
  ]

  def self.method_missing(method, *args, &block)
    if METHODS_TO_DELEGATE.include?(method)
      target_class = case Trixx::Application.config.trixx_db_type
                     when 'ORACLE' then TriggerOracle
                     when 'SQLITE' then TriggerSqlite
                     else
                       raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
                     end
      target_class.send(method, *args, &block)                                         # Call method with same name in target class
    else
      super
    end
  end

  def self.respond_to?(method, include_private = false)
    METHODS_TO_DELEGATE.include?(method) || super
  end


end