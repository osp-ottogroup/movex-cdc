class ColumnExpression < ApplicationRecord
  belongs_to  :table, optional: true  # optional: true is to avoid the extra lookup on reference for every DML. Integrity is ensured by FK constraint
  validate    :validate_unchanged_attributes
  validate    :validate_for_duplicates

  def validate_unchanged_attributes
    errors.add(:table_id,   "Change of table_id not allowed!")  if table_id_changed?  && self.persisted?
    errors.add(:operation,  "Change of table_id not allowed!")  if operation_changed? && self.persisted?
  end

  def validate_for_duplicates
    ColumnExpression.where(table_id: table_id, operation: operation).where.not(id: id).each do |ce|
      if ce.sql == sql
        errors.add(:base, "Duplicate entry found for table_id: #{table_id} and operation: #{operation} with same SQL. Existing record id: #{ce.id}")
      end
    end
  end

  # get hash with schema_name, table_name, column_name for activity_log
  def activity_structure_attributes
    {
      schema_name:  table.schema.name,
      table_name:   table.name,
    }
  end
end
