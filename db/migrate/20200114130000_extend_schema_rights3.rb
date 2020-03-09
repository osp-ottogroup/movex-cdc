class ExtendSchemaRights3 < ActiveRecord::Migration[6.0]

  def change
    add_index :schema_rights, [:user_id, :schema_id], name: 'IX_SCHEMA_RIGHTS_LOGICAL_PKEY', unique: true
  end

end
