class Column < ApplicationRecord
  belongs_to :table
  attribute :yn_pending, :string, limit: 1, default: 'N'  # is changed column value waiting for being activated in new generated trigger

  def self.count_active(filter_hash)
    retval = 0
    Column.where(filter_hash).each do |c|
      retval +=1 if c.yn_log_insert == 'Y' || c.yn_log_update == 'Y' || c.yn_log_delete == 'Y'
    end
    retval
  end

  def to_json(*args)
    calc_yn_pending                                                             # Calculate pending state before returning values to GUI
    super.to_json(*args)
  end

  private
  # set yn_pending to 'Y' if any test requires this
  def calc_yn_pending
    oldest_change_dates = table.oldest_trigger_change_dates_per_operation       # Hash for I/U/D
    [
        {operation: 'I', yn_log: yn_log_insert},
        {operation: 'U', yn_log: yn_log_update},
        {operation: 'D', yn_log: yn_log_delete},
    ].each do |oper_hash|
      operation = oper_hash[:operation]
      if yn_pending == 'N' && oper_hash[:yn_log] == 'Y'                         # newer trigger should exists for operation to not be pending
        yn_pending = 'Y' if oldest_change_dates[operation].nil? || oldest_change_dates[operation] < created_at
      end

      if yn_pending == 'N' && oper_hash[:yn_log] == 'N'                         # no trigger should exist for operation to not be pending
        yn_pending = 'Y' unless oldest_change_dates[operation].nil?
      end
    end
  end
end
