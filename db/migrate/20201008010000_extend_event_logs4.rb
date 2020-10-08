class ExtendEventLogs4 < ActiveRecord::Migration[6.0]
  def change
    add_column :event_logs, :retry_count, :integer, precision: 4, null: false, default: 0,  comment: 'Number of processing retries after error'
  end
end