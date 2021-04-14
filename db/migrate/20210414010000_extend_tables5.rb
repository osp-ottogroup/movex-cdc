class ExtendTables5 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :initialization_filter,  :string, limit: 4000, null: true, comment: 'SQL filter expression to filter current content of table before transferred to Kafka as insert events at next trigger generation'
  end
end
