class ExtendActivityLogs1 < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :activity_logs, :users, name: 'fk_activity_logs_users'
  end
end


