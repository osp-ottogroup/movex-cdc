class ExtendTables6 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :initialization_order_by,  :string, limit: 4000, null: true, comment: 'Optionally sort current content of table before transferred to Kafka as insert events at next trigger generation'
  end
end
