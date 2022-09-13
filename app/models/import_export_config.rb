require 'exception_helper'

class ImportExportConfig
  def initialize
    super
  end

  # get relevant column names for a AR class
  def self.extract_column_names(ar_class)
    # extract column names without id, *_id, timestamps and lock_version
    ar_class.columns.select{|c| !['id', 'created_at', 'updated_at', 'lock_version'].include?(c.name) && !c.name.match?(/_id$/)}.map{|c| c.name}
  end

  # export schema info for all or one schemas
  # @param single_schema_name nil for all schemas or limited for one schema
  def export(single_schema_name: nil)
    schema_columns        = self.class.extract_column_names(Schema)
    table_columns         = self.class.extract_column_names(Table)
    column_columns        = self.class.extract_column_names(Column)
    condition_columns     = self.class.extract_column_names(Condition)
    schema_right_columns  = self.class.extract_column_names(SchemaRight)

    schemas_list = []
    Schema.all.select{|s| single_schema_name.nil? || single_schema_name == s.name}.each do |schema|
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

    users_list = []
    User.all.each do |user|
      user_hash = {}
      self.class.extract_column_names(User).each do |c|
        user_hash[c] = user.send(c)                                             # call method by name
      end
      users_list << user_hash
    end

    export_data = Hash.new
    export_data['schemas']  = schemas_list
    export_data['users']    = users_list

    Rails.logger.debug('ImportExportConfig.export'){"Generated export:\n#{JSON.pretty_generate(export_data)}"}
    export_data
  end

  # import schema data
  # @param json_data            Hash with list of schema objects and list of user objects
  # @param schema_name_to_pick  Single schema name which should be imported out of the whole list of schemas, nil = import all schemas in list
  def import_schemas(import_hash, schema_name_to_pick: nil)
    raise "Parameter import_hash is not a Hash"   unless import_hash.is_a? Hash
    raise "Object users is not an array"   unless import_hash['users'].instance_of? Array
    raise "Object schemas is not an array" unless import_hash['schemas'].instance_of? Array
    raise "Schema '#{schema_name_to_pick}' does not exist in import data" if !schema_name_to_pick.nil? && import_hash['schemas'].find{|s| s['name'] == schema_name_to_pick }.nil?

    # Ensure all users exist in DB that are referenced in schema_rights
    import_hash['schemas']&.each do |schema_hash|
      schema_hash['schema_rights']&.each do |schema_right_hash|
        if User.where(email: schema_right_hash['email']).count == 0             # User does not exists in DB
          user_hash = import_hash['users'].find{|u| u['email'] == schema_right_hash['email']}
          raise "User with email '#{schema_right_hash['email']}' doesn't exist neither in the DB nor in the user list of import data!" if user_hash.nil?
          User.new(
            email:      user_hash['email'],
            db_user:    user_hash['db_user'],
            first_name: user_hash['first_name'],
            last_name:  user_hash['last_name'],
            yn_account_locked: 'Y'
          ).save! # create as locked user for reference
        end
      end
    end

    # Deactivate schemas which are not part of full import
    if schema_name_to_pick.nil?
      Schema.all.each do |schema|
        if import_hash['schemas'].find{|s| s['name'] == schema.name}.nil?       # existing schema not in list
          deactivate_surplus_schema(schema)                                     # Deactivate, not physically delete
        end
      end
    end

    import_hash['schemas'].select{|s| schema_name_to_pick.nil? || schema_name_to_pick == s['name'] }.each do |schema_hash|
      existing_schema = Schema.where(name: schema_hash['name']).first
      if existing_schema
        update_existing_schema(schema_hash, existing_schema)
      else                                                                      # create new schema with content
        import_new_schema(schema_hash)
      end
    end
  end

  # import an array of user configurations
  # Update existing users
  # Add missing users
  # Don't touch existing users that are not part of import list
  def import_users(import_data)
    raise "Parameter users is not an array" unless import_data['users'].instance_of? Array

    Rails.logger.info('ImportExportConfig'){'Importing Users'}
    import_data['users']&.each do |user_hash|
      existing_user = User.find_by_email_case_insensitive user_hash['email']
      if existing_user
        Rails.logger.info('ImportExportConfig'){ "Updating User #{user_hash.inspect}" }
        existing_user.update! user_hash
      else
        Rails.logger.info('ImportExportConfig'){ "New User #{user_hash.inspect}" }
        User.new(user_hash).save!
      end
    end
  end

  private

  # Create hash with columns of object
  def generate_export_object(exp_obj, columns)
    return_hash = {}
    columns.each do |column|
      return_hash[column] = exp_obj.send(column)
    end
    return_hash
  end

  # deactivate schemas structures without physically delete it
  def deactivate_surplus_schema(schema)
    # remove all rights for schema to make it unvisible for users
    schema.schema_rights.each do |sr|
      sr.destroy!
    end

    # Hide all tables but let them physically exist with the origin ID if triggers are still active for that tables
    schema.tables.each do |t|
      t.mark_hidden
    end
  end

=begin
  # adjust sequences to the highest used ID +1
  def adjust_sequences
    set_sequence = proc do |ar_class|
      curr_val =
        case MovexCdc::Application.config.db_type
        when 'ORACLE' then Database.select_one("SELECT Last_Number FROM User_Sequences WHERE Sequence_Name = :seq_name", { seq_name: ar_class.sequence_name})
        when 'SQLITE' then Database.select_one("SELECT seq FROM sqlite_sequence WHERE name = '#{ar_class.table_name}'")
        end
      curr_val = 1 if curr_val.nil?
      max_val = Database.select_one("SELECT MAX(ID) FROM #{ar_class.table_name}")
      max_val = 1 if max_val.nil?
      Rails.logger.debug('ImportExportConfig.adjust_sequences'){ "Increase sequence for table #{ar_class.table_name} from #{curr_val} to #{max_val}" } if curr_val < max_val
      case MovexCdc::Application.config.db_type
      when 'ORACLE' then
        curr_val.upto(max_val-1) do
          Database.select_one "SELECT #{ar_class.sequence_name}.NextVal FROM DUAL"
        end
      when 'SQLITE' then
        Database.execute "UPDATE sqlite_sequence SET seq = :max_val WHERE name = '#{ar_class.table_name}'", binds: { max_val: max_val}
      end
    end

    set_sequence.call(User)
    set_sequence.call(Schema)
    set_sequence.call(Table)
    set_sequence.call(Column)
    set_sequence.call(Condition)
    set_sequence.call(SchemaRight)
  end
=end

  # list of columns for import which are: relevant for AR class, existing in import structure, are not substructure-arrays
  def relevant_import_data(record_hash, ar_class)
    result = {}
    relevant_ar_columns = self.class.extract_column_names(ar_class)
    record_hash.each do |key, value|
      if !relevant_ar_columns.find{|c| c == key}.nil? &&                        # Hash entry in relevant AR columns
        value.class != Array                                                    # Entry is not a substructure
        result[key] = value
      end
    end
    result
  end

  # create the whole schema structure for a new schema
  # Transaction handling is done by calling controller
  def import_new_schema(schema_hash)
    schema = Schema.new(relevant_import_data(schema_hash, Schema))
    schema.save!
    schema_hash['tables']&.each do |table_hash|
      insert_new_table(table_hash, schema)
    end
    schema_hash['schema_rights']&.each do |schema_right_hash|
      user_id = User.where(email: schema_right_hash['email']).first&.id
      SchemaRight.new(relevant_import_data(schema_right_hash, SchemaRight).merge('schema_id' => schema.id, 'user_id' => user_id)).save!
    end
  end

  # Transaction handling is done by calling controller
  def update_existing_schema(schema_hash, existing_schema)
    existing_schema.update!(relevant_import_data(schema_hash, Schema))

    # deactivate tables of schema missed in current import data
    Table.where(schema_id: existing_schema.id).each do |table|
      if schema_hash['tables'].find{|t| t['name'] == table.name}.nil?            # existing table not found in import data for schema
        table.mark_hidden
      end
    end

    schema_hash['tables']&.each do |table_hash|
      raise "Table element of schema '#{schema_hash['name']}' should be of type Hash but is a #{table_hash.class} with content '#{table_hash}'" unless table_hash.is_a? Hash
      existing_table = Table.where(schema_id: existing_schema.id, name: table_hash['name']).first
      if existing_table.nil?
        insert_new_table(table_hash, existing_schema)
      else
        update_table(table_hash, existing_table)
      end
    end

    # delete schema_rights of table missed in current import data
    SchemaRight.where(schema_id: existing_schema.id).each do |schema_right|
      if schema_hash['schema_rights'].find{|sr| sr['email'] == schema_right.user.email}.nil? # existing schema_right not found in import data for table
        schema_right.destroy!
      end
    end

    # Insert or update schema_rights
    schema_hash['schema_rights']&.each do |schema_right_hash|
      raise "Schema_Right element of schema '#{schema_hash['name']}' should be of type Hash but is a #{schema_right_hash.class} with content '#{schema_right_hash}'" unless schema_right_hash.is_a? Hash
      user = User.where( email: schema_right_hash['email']).first
      raise "User with email = '#{schema_right_hash['email']}' does not exist in table Users" if user.nil?
      existing_schema_right = SchemaRight.where(schema_id: existing_schema.id, user_id: user.id).first
      if existing_schema_right.nil?
        SchemaRight.new(relevant_import_data(schema_right_hash, SchemaRight).merge('schema_id' => existing_schema.id, 'user_id' => user.id)).save!
      else
        existing_schema_right.update!(relevant_import_data(schema_right_hash, SchemaRight))
      end
    end
  end

  # create a new table that is missing in DB
  # @param table_hash   Fragment of import data for one table
  # @schema             Existing Schema record
  def insert_new_table(table_hash, schema)
    table = Table.new(relevant_import_data(table_hash, Table).merge('schema_id' => schema.id))
    table.save!
    table_hash['columns']&.each do |column_hash|
      raise "Column element of table '#{table_hash['name']}' should be of type Hash but is a #{column_hash.class} with content '#{column_hash}'" unless column_hash.is_a? Hash
      Column.new(relevant_import_data(column_hash, Column).merge('table_id' => table.id)).save!
    end
    table_hash['conditions']&.each do |condition_hash|
      raise "Condition element of table '#{table_hash['name']}' should be of type Hash but is a #{condition_hash.class} with content '#{condition_hash}'" unless condition_hash.is_a? Hash
      Condition.new(relevant_import_data(condition_hash, Condition).merge('table_id' => table.id)).save!
    end
  end

  # update an existing table
  # @param table_hash   Fragment of import data for one table
  # @schema             Existing Schema record
  def update_table(table_hash, table)
    table.update!(relevant_import_data(table_hash, Table))

    # delete columns of table missed in current import data
    Column.where(table_id: table.id).each do |column|
      if table_hash['columns'].find{|t| t['name'] == column.name}.nil?          # existing column not found in import data for table
        column.destroy!
      end
    end

    # Insert or update columns
    table_hash['columns']&.each do |column_hash|
      raise "Column element of table '#{table_hash['name']}' should be of type Hash but is a #{column_hash.class} with content '#{column_hash}'" unless column_hash.is_a? Hash
      existing_column = Column.where(table_id: table.id, name: column_hash['name']).first
      if existing_column.nil?
        Column.new(relevant_import_data(column_hash, Column).merge('table_id' => table.id)).save!
      else
        existing_column.update!(relevant_import_data(column_hash, Column))
      end
    end

    # delete conditions of table missed in current import data
    Condition.where(table_id: table.id).each do |condition|
      if table_hash['conditions'].find{|c| c['operation'] == condition.operation}.nil? # existing condition not found in import data for table
        condition.destroy!
      end
    end

    # Insert or update conditions
    table_hash['conditions']&.each do |condition_hash|
      raise "Condition element of table '#{table_hash['name']}' should be of type Hash but is a #{condition_hash.class} with content '#{condition_hash}'" unless condition_hash.is_a? Hash
      existing_condition = Condition.where(table_id: table.id, operation: condition_hash['operation']).first
      if existing_condition.nil?
        Condition.new(relevant_import_data(condition_hash, Condition).merge('table_id' => table.id)).save!
      else
        existing_condition.update!(relevant_import_data(condition_hash, Condition))
      end
    end
  end
end
