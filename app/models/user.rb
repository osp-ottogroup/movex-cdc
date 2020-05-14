class User < ApplicationRecord
  has_many :activity_logs
  has_many :schema_rights
  validate :validate_schema_name
  validates :yn_admin, acceptance: { accept: ['Y', 'N'] }

  def validate_schema_name
    unless DbSchema.valid_schema_name?(db_user)
      errors.add(:db_user, "User '#{db_user}' does not exists in database")
    end
  end
end
