class ExtendEventLogs3 < ActiveRecord::Migration[6.0]
  def change
    add_column :event_logs, :last_error_time, :timestamp, null: true,  comment: 'Last time processing resulted in error'
  end
end


