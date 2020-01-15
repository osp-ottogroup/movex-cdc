class CreateActivityLogs < ActiveRecord::Migration[6.0]
  def change
    create_table :activity_logs do |t|
      t.references  :user,           null: false,  comment: 'Reference to user'
      t.string      :schema_name,   limit: 256, null: true,   comment: 'Name of schema'
      t.string      :table_name,    limit: 256, null: true,   comment: 'Name of table'
      t.string      :column_name,   limit: 256, null: true,   comment: 'Name of column'
      t.string      :action,        limit: 1024, null: false, comment: 'Executed action / activity'
      t.timestamps
    end
  end
end


