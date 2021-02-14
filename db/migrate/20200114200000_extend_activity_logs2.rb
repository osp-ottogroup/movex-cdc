class ExtendActivityLogs2 < ActiveRecord::Migration[6.0]
  def up
    add_index :activity_logs, [:schema_name, :table_name, :column_name], name: 'IX_ACTIVITY_LOG_TABCOL'
  end

  def down
    # Rails 6.1.2.1 throws error:
    # > ArgumentError (No indexes found on statistics with the options provided.)
    # for "change" method if columns are part of remove_index
    remove_index :activity_logs, name: 'IX_ACTIVITY_LOG_TABCOL'
  end
end


