class Condition < ApplicationRecord
  belongs_to :table
  validate    :validate_unchanged_attributes

  def validate_unchanged_attributes
    errors.add(:table_id,   "Change of table_id not allowed!")  if table_id_changed?  && self.persisted?
    errors.add(:operation,  "Change of table_id not allowed!")  if operation_changed? && self.persisted?
  end

  # get hash with schema_name, table_name, column_name for activity_log
  def activity_structure_attributes
    {
      schema_name:  table.schema.name,
      table_name:   table.name,
    }
  end

end
