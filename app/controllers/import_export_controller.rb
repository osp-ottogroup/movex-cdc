require 'json'

class ImportExportController < ApplicationController

  def export
    out = export_schemas(Schema.all)
    render json: JSON.pretty_generate(out)
  end

  def export_schema
    schemas = Schema.where(name: params[:schema])
    if schemas.count > 0
      out = export_schemas(schemas)
      render json: JSON.pretty_generate(out)
    else
      render json: {errors: ["Schema not found with name '#{params[:schema]}'"]}, status: :not_found
    end
  end

  def import
    logger.info 'Starting import of trigger configuration'
    params.require([:users, :schemas])

    # Columns without relation and timestamp
    user_columns          = extract_column_names(User)
    schema_columns        = extract_column_names(Schema)
    table_columns         = extract_column_names(Table)
    column_columns        = extract_column_names(Column)
    condition_columns     = extract_column_names(Condition)
    schema_right_columns  = extract_column_names(SchemaRight)

    ActiveRecord::Base.transaction do
      logger.info 'Updating Users'
      params[:users].each do |user|
        user_params = user.permit(user_columns.map{|c| c.to_sym})
        existing_user = User.find_by_email_case_insensitive user[:email]
        if existing_user
          logger.info "Updating User #{user_params.inspect}"
          existing_user.update! user_params
        else
          logger.info "New User #{user_params.inspect}"
          User.new(user_params).save!
        end
      end

      params[:schemas].each do |schema|
        logger.info "Importing Schema #{schema}"
        schema_params = schema.permit(schema_columns.map{|c| c.to_sym},
                                      [tables: [table_columns.map{|c| c.to_sym},
                                                [columns: [column_columns.map{|c| c.to_sym}]],
                                                [conditions: [condition_columns.map{|c| c.to_sym}]]
                                      ]],
                                      schema_rights: [schema_right_columns.map{|c| c.to_sym}].append(:email))
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

        set_object_attribs_from_hash(import_schema, schema_params, schema_columns)
        import_schema.save!

        schema_params[:tables].each do |table|
          new_table = Table.new table.permit(table_columns.map{|c| c.to_sym}) # prevent relations from params
          new_table.schema_id = import_schema.id
          new_table.save!
          import_schema.tables << new_table

          table[:columns].each do |column|
            new_column = Column.new column.permit(column_columns.map{|c| c.to_sym}) # prevent possible relations from params
            new_column.table_id = new_table.id
            new_column.save!
            new_table.columns << new_column
          end

          table[:conditions].each do |condition|
            new_condition = Condition.new condition.permit(condition_columns.map{|c| c.to_sym}) # prevent possible relations from params
            new_condition.table_id = new_table.id
            new_condition.save!
            new_table.conditions << new_condition
          end
        end

        schema_params[:schema_rights].each do |schema_right|
          new_right = SchemaRight.new schema_right.permit(schema_right_columns.map{|c| c.to_sym}) # prevent possible relations from params
          new_right.schema = import_schema
          existing_user = User.find_by_email_case_insensitive schema_right[:email]
          new_right.user = existing_user
          new_right.save!
        end
      end
    end
  end

  def export_schemas(schemas)
    schema_columns        = extract_column_names(Schema)
    table_columns         = extract_column_names(Table)
    column_columns        = extract_column_names(Column)
    condition_columns     = extract_column_names(Condition)
    schema_right_columns  = extract_column_names(SchemaRight)
    user_columns          = extract_column_names(User)

    schemas_list = []
    schemas.each do |schema|
      schema_hash = generate_export_object(schema, schema_columns)

      schema_hash['tables'] = []
      schema.tables.each do |table|
        table_hash = generate_export_object(table, table_columns)

        table_hash['columns'] = []
        table.columns.each do |column|
          table_hash['columns'] << generate_export_object(column, column_columns)
        end

        table_hash['conditions'] = []
        table.conditions.each do |condition|
          table_hash['conditions'] << generate_export_object(condition, condition_columns)
        end
        schema_hash['tables'] << table_hash
      end

      schema_hash['schema_rights'] = []
      schema.schema_rights.each do |schema_right|
        schema_rights_hash = generate_export_object(schema_right, schema_right_columns)
        schema_rights_hash['email'] = schema_right.user.email
        schema_hash['schema_rights'] << schema_rights_hash
      end
      schemas_list << schema_hash
    end

    # extract column names without id and *_id and timestamps
    users_list = []
    User.all.each do |user|
      user_hash = {}
      user_columns.each do |c|
        user_hash[c] = user.send(c)                                             # call method by name
      end
      users_list << user_hash
    end

    out = Hash.new
    out['schemas'] = schemas_list
    out['users'] = users_list
    out
  end

  private
  def extract_column_names(ar_class)
    # extract column names without id, *_id, timestamps and lock_version
    ar_class.columns.select{|c| !['id', 'created_at', 'updated_at', 'lock_version'].include?(c.name) && !c.name.match?(/_id$/)}.map{|c| c.name}
  end

  # Create hash with columns of object
  def generate_export_object(exp_obj, columns)
    return_hash = {}
    columns.each do |column|
      return_hash[column] = exp_obj.send(column)
    end
    return_hash
  end

  def set_object_attribs_from_hash(ar_object, hash, columns)
    hash.each do |key, value|
      if value.class != Array
        if columns.include?(key)
          ar_object.send("#{key}=", value)
        else
          Rails.logger.warn "ImportExportController.set_object_attribs_from_hash: Column #{key} of class #{ar_object.class} does not exists in TriXX model any more"
        end
      end
    end
  end

end