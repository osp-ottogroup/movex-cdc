class Schema < ApplicationRecord
  has_many :tables
  has_many :schema_rights
end
