class ExtendEventLogs3 < ActiveRecord::Migration[6.0]
  def change
    add_column :event_logs, :msg_key, :string, limit: 4000, null: true, comment: 'Optional Kafka message key to ensure all messages of same key are stored in same partition'
  end
end
