class User < ApplicationRecord
  # validates :email, presence: true, uniqueness: true # let database validate uniqueness and not null
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  before_validation { self.db_user = self.db_user&.downcase } # store db-user in downcase always
end
