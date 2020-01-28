class ExtendSchemaRights3 < ActiveRecord::Migration[6.0]

  def change
    add_index :schema_rights, [:user_id, :schema_id], name: 'ix_schema_rights_logical_pkey', unique: true
  end

end
