class User < ApplicationRecord
  has_many :activity_logs
  has_many :schema_rights

  validates :yn_admin, acceptance: { accept: ['Y', 'N'] }
  before_validation { self.db_user = self.db_user&.downcase } # store db-user in downcase always
end
