class User < ApplicationRecord
  # validates :email, presence: true, uniqueness: true # let database validate uniqueness and not null
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end
