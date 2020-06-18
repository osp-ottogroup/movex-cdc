class ExtendSchemaRights4 < ActiveRecord::Migration[6.0]

  def change
    add_column :schema_rights, :lock_version, :integer, null: false, default: 0, comment: 'Version for optimistic locking'
  end
end
