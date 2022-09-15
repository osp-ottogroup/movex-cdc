class CreateActivityLogs < ActiveRecord::Migration[6.0]
  def change
    create_table :activity_logs do |t|
      t.references  :user,           null: false,  comment: 'Reference to user'
      t.string      :schema_name,   limit: 256,   null: true,   comment: 'Name of schema'
      t.string      :table_name,    limit: 256,   null: true,   comment: 'Name of table'
      t.string      :column_name,   limit: 256,   null: true,   comment: 'Name of column'
      t.text        :action,                      null: false,  comment: 'Executed action / activity'
      t.string      :client_ip,     limit: 40,    null: true,   comment: 'Client IP address for request'
      t.timestamps
    end
  end
end


