class TablesEncryptionKeys < ActiveRecord::Migration[6.0]
  def change
    add_reference :tables, :encryption_key, null:true, foreign_key: { name: "fk_tables_encryption_key"}, index: { name: 'IX_TABLES_ENCRYPTION_KEY' }
  end
end