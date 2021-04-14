class DbTrigger < ApplicationRecord

  # delegate method calls to DB-specific implementation classes
  @@METHODS_TO_DELEGATE = [
      :build_trigger_name,
      :find_all_by_schema_id,
      :find_all_by_table,
      :find_by_table_id_and_trigger_name,
  ]

  def self.method_missing(method, *args, &block)
    if @@METHODS_TO_DELEGATE.include?(method)
      target_class = case Trixx::Application.config.trixx_db_type
                     when 'ORACLE' then DbTriggerGeneratorOracle
                     when 'SQLITE' then DbTriggerGeneratorSqlite
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
  # Parameter: - schema_id:     schema all pending triggers are generated for
  #            - user_options:  User/request attributes for activity logging (:user_id, :client_ip_info)
  #            - dry_run:       compile triggers or not
  #            - table_id_list: Array of table-IDs to generate triggers for, nil=all
  # return:    { schema_id:, successes: [], errors: []}
  def self.generate_schema_triggers(schema_id:, user_options:, dry_run: false, table_id_list: nil)
    schema = Schema.find schema_id
    generator = case Trixx::Application.config.trixx_db_type
                when 'ORACLE' then DbTriggerGeneratorOracle.new(schema_id: schema_id, user_options: user_options, dry_run: dry_run)
                when 'SQLITE' then DbTriggerGeneratorSqlite.new(schema_id: schema_id, user_options: user_options, dry_run: dry_run)
                else
                  raise "Unsupported value for Trixx::Application.config.trixx_db_type: '#{Trixx::Application.config.trixx_db_type}'"
                end

    Table.where(schema_id: schema_id).each do |table|
      if table_id_list.nil? || table_id_list.include?(table.id)
        generator.generate_table_triggers(table_id: table.id) # check if drop or create trigger is to do
      end
    end

    generator.errors.each do |error|
      Rails.logger.error "Error creating trigger #{error[:trigger_name]}"
      Rails.logger.error "#{error[:exception_class]}: #{error[:exception_message]}"
      Rails.logger.error "#{error[:sql]}"
    end

    # Log activities
    schema.update!(last_trigger_deployment: Time.now) if generator.errors.count == 0  # Flag trigger generation successful
    raise "DbTrigger.generate_triggers: :user_id missing in user_options hash"        unless user_options.has_key? :user_id
    raise "DbTrigger.generate_triggers: :client_ip_info missing in user_options hash" unless user_options.has_key? :client_ip_info
    generator.successes.each do |success_trigger|
      action = "Trigger #{success_trigger[:trigger_name]} successful created: #{success_trigger[:sql]}"[0, 500] # should be smaller than 1000 bytes
      ActivityLog.new(user_id: user_options[:user_id], schema_name: schema.name, table_name: success_trigger[:table_name], action: action, client_ip: user_options[:client_ip_info]).save!
    end
    generator.errors.each do |error_trigger|
      action = "Trigger #{error_trigger[:trigger_name]} created but with errors: #{error_trigger[:exception_class]}:#{error_trigger[:exception_message]} :  #{error_trigger[:sql]}"[0, 500] # should be smaller than 1000 bytes
      ActivityLog.new(user_id: user_options[:user_id], schema_name: schema.name, table_name: error_trigger[:table_name], action: action, client_ip: user_options[:client_ip_info]).save!
    end

    { successes: generator.successes, errors: generator.errors, load_sqls: generator.load_sqls}
  end
end