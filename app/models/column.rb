class Column < ApplicationRecord
  belongs_to :table

  def self.count_active(filter_hash)
    retval = 0
    Column.where(filter_hash).each do |c|
      retval +=1 if c.yn_log_insert == 'Y' || c.yn_log_update == 'Y' || c.yn_log_delete == 'Y'
    end
    retval
  end
end
