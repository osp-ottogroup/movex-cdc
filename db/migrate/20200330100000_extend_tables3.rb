class ExtendTables3 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :topic, :string, limit: 255, null: true, comment: 'Topic name for table. Topic name of schema is used s default if Null'
  end
end

