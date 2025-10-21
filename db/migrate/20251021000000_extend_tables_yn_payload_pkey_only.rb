class ExtendTablesYnPayloadPkeyOnly < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :yn_payload_pkey_only,  :string, limit: 1, null: false, default: 'N',  comment: 'Should payload contain only the primary key columns but not the other marked columns?.'
  end
end