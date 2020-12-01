class ExtendTables3 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :yn_record_txid,  :string, limit: 1, null: false, default: 'N',  comment: 'Record transaction-ID for events of this table?.'
  end
end