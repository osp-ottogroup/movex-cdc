class Column < ApplicationRecord
  belongs_to :table
  attribute :yn_pending, :string, limit: 1, default: 'Y'  # is changed column value waiting for being activated in new generated trigger

  def self.count_active(filter_hash)
    retval = 0
    Column.where(filter_hash).each do |c|
      retval +=1 if c.yn_log_insert == 'Y' || c.yn_log_update == 'Y' || c.yn_log_delete == 'Y'
    end
    retval
  end
end
