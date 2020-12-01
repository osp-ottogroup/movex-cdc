class ExtendEventLogs5 < ActiveRecord::Migration[6.0]
  def change
    # Max. length of local transaction ID is 22 for Oracle
    add_column :event_logs, :transaction_id,  :string, limit: 100, null: true, comment: 'Original database transaction ID (if recorded)'
  end
end