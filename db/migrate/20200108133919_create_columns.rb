class CreateColumns < ActiveRecord::Migration[6.0]
  def change
    create_table :columns, comment: 'Columns with flags for DML operation to trigger' do |t|
      t.references :table,                    null: false,              comment: 'Reference to table'
      t.string  :name,          limit: 256,   null: false,              comment: 'Column name of database table'
      t.string  :info,          limit: 1000,  null: true,               comment: 'Additional info'
      t.string  :yn_log_insert, limit: 1,     null: false,              comment: 'Log this column at insert operation (Y/N)'
      t.string  :yn_log_update, limit: 1,     null: false,              comment: 'Log this column at update operation (Y/N)'
      t.string  :yn_log_delete, limit: 1,     null: false,              comment: 'Log this column at delete operation (Y/N)'
      t.integer :lock_version,                null: false,  default: 0, comment: 'Version for optimistic locking'
      t.timestamps
    end
  end
end
