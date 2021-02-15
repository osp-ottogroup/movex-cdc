class Condition < ApplicationRecord
  belongs_to :table
  validate    :validate_unchanged_attributes

  def validate_unchanged_attributes
    errors.add(:table_id,   "Change of table_id not allowed!")  if table_id_changed?  && self.persisted?
    errors.add(:operation,  "Change of table_id not allowed!")  if operation_changed? && self.persisted?
  end

end
