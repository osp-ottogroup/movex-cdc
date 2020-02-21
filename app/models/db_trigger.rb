class DbTrigger

  # delegate method calls to DB-specific implementation classes
  METHODS_TO_DELEGATE = [
      :find_all_by_schema_id,
      :find_by_table_id_and_trigger_name,
  ]

  def self.method_missing(method, *args, &block)
    if METHODS_TO_DELEGATE.include?(method)
      target_class = case Trixx::Application.config.trixx_db_type
                     when 'ORACLE' then DbTriggerOracle
                     when 'SQLITE' then DbTriggerSqlite
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

  # Generate triggers for schema
  def self.generate_triggers(schema_id)
    # TODO: Implement
    target_trigger_data = []                                                    # Hash with target trigger states for schema

    # Build hash structure with data for trigger generation
    Table.where(schema_id: schema_id).each do |table|
      if Column.count_active(table_id: table.id) > 0                            # Suppress tables without active columns in result
        table_data = { table_id: table.id, table_name: table.name}
        operations_data = []
        [ { short: 'I', col: :yn_log_insert },
          { short: 'U', col: :yn_log_update },
          { short: 'D', col: :yn_log_delete }
        ].each do |operation|
          if Column.count_active( {table_id: table.id, operation[:col] => 'Y'} ) > 0  # Suppress tables/operations without active columns in result
            operation_data = { operation: operation[:short] }

            Condition.where(table_id: table.id, operation: operation[:short] ).each do |condition|  # there is max. one or no record for filter conditions
              operation_data[:condition] = condition.filter
            end

            columns_data = []
            Column.where(table_id: table.id, operation[:col] => 'Y').each do |column|
              columns_data << { column_name: column.name }
            end
            operation_data[:columns] = columns_data

            operations_data << operation_data
          end
        end
        # Finish processing of table
        table_data[:operations] = operations_data
        target_trigger_data << table_data
      end
    end

    # Delegate to DB-specific classes
    case Trixx::Application.config.trixx_db_type
     when 'ORACLE' then result = DbTriggerOracle.generate_db_triggers(schema_id, target_trigger_data)
     when 'SQLITE' then result = DbTriggerSqlite.generate_db_triggers(schema_id, target_trigger_data)
     else
       raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
    end

    result[:errors].each do |error|
      Rails.logger.error "Error creating trigger #{error[:trigger_name]}"
      Rails.logger.error "#{error[:exception_class]}: #{error[:exception_message]}"
      Rails.logger.error "#{error[:sql]}"
    end

    result
  end


end