class User < ApplicationRecord
  has_many :activity_logs
  has_many :schema_rights

  # validates :email, presence: true, uniqueness: true # let database validate uniqueness and not null
  # validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }  # allow admin as email
  before_validation { self.db_user = self.db_user&.downcase } # store db-user in downcase always
end
