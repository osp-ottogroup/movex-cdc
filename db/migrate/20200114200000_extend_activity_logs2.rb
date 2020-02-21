class ExtendActivityLogs2 < ActiveRecord::Migration[6.0]
  def change
    add_index :activity_logs, [:schema_name, :table_name, :column_name], name: 'IX_ACTIVITY_LOG_TABCOL'
  end
end


