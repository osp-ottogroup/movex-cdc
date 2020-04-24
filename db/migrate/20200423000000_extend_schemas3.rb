class ExtendSchemas3 < ActiveRecord::Migration[6.0]
  def change
    add_column :schemas, :last_trigger_deployment, :timestamp, null: true, comment: 'Timestamp of last successful trigger deployment for schema (no matter if there have been changes for triggers or not)'
  end
end

