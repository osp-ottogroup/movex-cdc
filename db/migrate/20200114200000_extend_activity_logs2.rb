class ExtendActivityLogs2 < ActiveRecord::Migration[6.0]
  def change
    add_index :activity_logs, [:schema_name, :table_name, :column_name], name: 'ix_activity_log_tabcol'
  end
end


