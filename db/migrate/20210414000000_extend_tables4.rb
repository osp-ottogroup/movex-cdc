class ExtendTables4 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :yn_initialization,  :string, limit: 1, null: false, default: 'N', comment: 'Should current content of table be transferred to Kafka as insert events at next trigger generation?'
  end
end
