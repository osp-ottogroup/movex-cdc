class TriggerConfigController < ApplicationController

  def export
    out = export_schemas(Schema.all)
    render json: out
  end

  def export_schema
    schema = Schema.find(params[:schema])
    if schema
      out = export_schemas([schema])
      render json: out
    else
      render json: {errors: ['Schema not found']}, status: :not_found
    end
  end

  def import
    logger.info 'Starting import of trigger configuration'

    Schema.transaction do
      logger.info 'Updating Users'
      if params[:users] === nil
        params[:users] = []
      end
      params[:users].each do |user|
        user_params = user.permit(:email, :db_user, :first_name, :last_name, :yn_admin, :yn_account_locked, :failed_logons, :yn_hidden)
        existing_user = User.find_by_email_case_insensitive user[:email]
        if existing_user
          logger.info "Updating User #{user_params.inspect}"
          existing_user.update! user_params
        else
          logger.info "New User #{user_params.inspect}"
          new_user = User.new user_params
          new_user.save!
        end
      end

      if params[:schemas] === nil
        params[:schemas] = []
      end
      params[:schemas].each do |schema|
        logger.info "Importing Schema #{schema}"
        schema_params = schema.permit(:name, :topic, :last_trigger_deployment,
                                      [tables: [:name, :info, :topic, :kafka_key_handling, :fixed_message_key, :yn_hidden,
                                                [columns: [:name, :info, :yn_pending, :yn_log_insert, :yn_log_update, :yn_log_delete]],
                                                [conditions: [:operation, :filter]]]],
                                      schema_rights: [:name, :info])
        import_schema = Schema.find_by_name(schema_params[:name])
        if import_schema
          logger.info 'Found existing Schema "' + schema_params[:name] + '", going clean it'
          import_schema.tables.each do |table|
            table.columns.destroy_all
            table.conditions.destroy_all
            table.destroy
          end

          schema_rights = SchemaRight.where(schema_id: import_schema.id)
          schema_rights.destroy_all
        else
          import_schema = Schema.new
        end

        import_schema.name = schema_params[:name]
        import_schema.topic = schema_params[:topic]
        import_schema.last_trigger_deployment = schema_params[:last_trigger_deployment]
        import_schema.save!

        schema_params[:tables].each do |table|
          new_table = Table.new table.permit(:name, :info, :topic, :kafka_key_handling, :fixed_message_key, :yn_hidden)
          new_table.schema_id = import_schema.id
          new_table.save!
          import_schema.tables << new_table

          table[:columns].each do |column|
            new_column = Column.new column
            new_column.table_id = new_table.id
            new_column.save!
            new_table.columns << new_column
          end

          table[:conditions].each do |condition|
            new_condition = Condition.new condition
            new_condition.table_id = new_table.id
            new_condition.save!
            new_table.conditions << new_condition
          end
        end

        schema_params[:schema_rights].each do |schema_right|
          new_right = SchemaRight.new
          new_right.info = schema_right[:info]
          new_right.schema = import_schema
          existing_user = User.find_by_email_case_insensitive schema_right[:name]
          new_right.user = existing_user
          new_right.save!
        end
      end
    end
  end

  def export_schemas(schemas)
    schemas_list = []
    schemas.each do |schema|
      tables = Table.includes(:columns, :conditions).where(schema_id: schema.id)
      tables_list = []
      tables.each do |table|
        columns_list = []
        table.columns.each do |column|
          column_hash = {name: column.name, info: column.info, yn_pending: column.yn_pending,
                         yn_log_insert: column.yn_log_insert, yn_log_update: column.yn_log_update,
                         yn_log_delete: column.yn_log_delete}
          columns_list.append column_hash
        end

        table_hash = {name: table.name, info: table.info, topic: table.topic,
                      kafka_key_handling: table.kafka_key_handling, fixed_message_key: table.fixed_message_key,
                      yn_hidden: table.yn_hidden, columns: columns_list, conditions: table.conditions}
        tables_list.append table_hash
      end

      schema_rights_list = []
      schema_rights = SchemaRight.includes(:user).where(schema_id: schema.id)
      schema_rights.each do |schema_right|
        schema_right_hash = {name: schema_right.user.email, info: schema_right.info}
        schema_rights_list.append(schema_right_hash)
      end

      schema_hash = {name: schema.name, topic: schema.topic, last_trigger_deployment: schema.last_trigger_deployment,
                     tables: tables_list, schema_rights: schema_rights_list}
      schemas_list.append schema_hash
    end

    users_list = []
    User.all.each do |user|
      user_hash = {email: user.email, db_user: user.db_user, first_name: user.first_name, last_name: user.last_name,
                   yn_admin: user.yn_admin, yn_account_locked: user.yn_account_locked,
                   failed_logons: user.failed_logons, yn_hidden: user.yn_hidden}
      users_list.append user_hash
    end

    out = Hash.new
    out['schemas'] = schemas_list
    out['users'] = users_list
    out
  end
end