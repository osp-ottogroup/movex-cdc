class DbTrigger < ApplicationRecord

  # delegate method calls to DB-specific implementation classes
  @@METHODS_TO_DELEGATE = [
      :build_trigger_name,
      :find_all_by_schema_id,
      :find_all_by_table,
      :find_by_table_id_and_trigger_name,
      :generate_db_triggers
  ]

  def self.method_missing(method, *args, &block)
    if @@METHODS_TO_DELEGATE.include?(method)
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
    @@METHODS_TO_DELEGATE.include?(method) || super
  end

  # Generate triggers
  # Parameter: - schema_id: schema all pending triggers are generated for
  #            - user_options:   User/request attributes for activity logging (:user_id, :client_ip_info)
  def self.generate_triggers(schema_id, user_options)
    schema = Schema.find(schema_id)
    target_trigger_data = []                                                    # Hash with target trigger states for schema

    # Build hash structure with data for trigger generation
    Table.where(schema_id: schema_id).each do |table|
      if Column.count_active(table_id: table.id) > 0                            # Suppress tables without active columns in result
        table_data = { table_id: table.id, table_name: table.name, kafka_key_handling: table.kafka_key_handling, fixed_message_key: table.fixed_message_key}
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

    result = generate_db_triggers(schema_id, target_trigger_data)               # Delegate to DB-specific classes
    result[:errors].each do |error|
      Rails.logger.error "Error creating trigger #{error[:trigger_name]}"
      Rails.logger.error "#{error[:exception_class]}: #{error[:exception_message]}"
      Rails.logger.error "#{error[:sql]}"
    end

    # Log activities
    Schema.find(schema_id).update!(last_trigger_deployment: Time.now) if result[:errors].count == 0  # Flag trigger generation successful
    unless user_options.empty?
      raise "DbTrigger.generate_triggers: :user_id missing in user_options hash"        unless user_options.has_key? :user_id
      raise "DbTrigger.generate_triggers: :client_ip_info missing in user_options hash" unless user_options.has_key? :client_ip_info
      result[:successes].each do |success_trigger|
        action = "Trigger #{success_trigger[:trigger_name]} successful created: #{success_trigger[:sql]}"[0, 500] # should be smaller than 1000 bytes
        ActivityLog.new(user_id: user_options[:user_id], schema_name: schema.name, table_name: success_trigger[:table_name], action: action, client_ip: user_options[:client_ip_info]).save!
      end
      result[:errors].each do |error_trigger|
        action = "Trigger #{error_trigger[:trigger_name]} created but with errors: #{error_trigger[:exception_class]}:#{error_trigger[:exception_message]} :  #{error_trigger[:sql]}"[0, 500] # should be smaller than 1000 bytes
        ActivityLog.new(user_id: user_options[:user_id], schema_name: schema.name, table_name: error_trigger[:table_name], action: action, client_ip: user_options[:client_ip_info]).save!
      end
    end

    result
  end

end