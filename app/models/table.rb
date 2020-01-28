class Table < ApplicationRecord
  belongs_to :schema
  has_many :columns
  has_many :conditions
end
