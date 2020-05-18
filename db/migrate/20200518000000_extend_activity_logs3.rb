class ExtendActivityLogs3 < ActiveRecord::Migration[6.0]
  def change
    add_column :activity_logs, :client_ip, :string, limit: 40, null: true, comment: 'Client IP address for request'
  end
end


