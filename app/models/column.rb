class Column < ApplicationRecord
  belongs_to :table
  attribute   :yn_pending, :string, limit: 1, default: 'N'  # is changed column value waiting for being activated in new generated trigger
  validate    :validate_yn_columns
  validate    :validate_unchanged_attributes

  def validate_yn_columns
    validate_yn_column :yn_log_insert
    validate_yn_column :yn_log_update
    validate_yn_column :yn_log_delete
  end

  def validate_unchanged_attributes
    errors.add(:table_id, "Change of table_id not allowed!")  if table_id_changed? && self.persisted?
    errors.add(:name,     "Change of name not allowed!")      if name_changed?     && self.persisted?
  end

  def self.count_active(filter_hash)
    retval = 0
    Column.where(filter_hash).each do |c|
      retval +=1 if c.yn_log_insert == 'Y' || c.yn_log_update == 'Y' || c.yn_log_delete == 'Y'
    end
    retval
  end

  # Mark columns for operation or not
  # operation (I/U/D), tag (Y/N)
  def self.tag_operation_for_all_columns(table_id, operation, tag)
    ActiveRecord::Base.transaction do
      # for tag == 'N' it is not necessary to have existing records in COLUMN because default is 'N'
      # Important because dropping a not marked column in real table leaves no remaining artifacts in MOVEX CDC this way
      if tag == 'Y'
        # Ensure all real table columns exist in table COLUMNS
        table = Table.find(table_id)
        db_columns = DbColumn.all_by_table(table.schema.name, table.name)
        column_names = Column.where(table_id: table_id).map{|c| c.name.downcase}
        db_columns.select{|c| !column_names.include?(c['name'].downcase)}.each do |dbc|    # create missing records in COLUMNS
        Column.new(table_id: table.id, name: dbc['name'], yn_log_insert: 'N', yn_log_update: 'N', yn_log_delete: 'N').save!
        end
      end

      Database.execute("UPDATE Columns SET #{affected_colname_by_operation(operation)} = :tag WHERE Table_ID = :table_id", tag: tag, table_id: table_id)
    end
  end

  def as_json(*args)
    calc_yn_pending                                                             # Calculate pending state before returning values to GUI
    super.as_json(*args)
  end

  private
  # set yn_pending to 'Y' if change is younger than last trigger generation check
  def calc_yn_pending
    last_trigger_deployment = table.schema.last_trigger_deployment
    self.yn_pending = last_trigger_deployment.nil? || last_trigger_deployment < updated_at ? 'Y' : 'N'
  end

  def self.affected_colname_by_operation(operation)
    case operation
    when 'I' then 'yn_log_insert'
    when 'U' then 'yn_log_update'
    when 'D' then 'yn_log_delete'
    end
  end

  # get hash with schema_name, table_name, column_name for activity_log
  def activity_structure_attributes
    {
      schema_name:  table.schema.name,
      table_name:   table.name,
      column_name:  self.name
    }
  end


end
