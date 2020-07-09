class CreateSchemaRights < ActiveRecord::Migration[6.0]

  def change
    create_table :schema_rights do |t|
      t.references  :user,                        null: false,              comment: 'Reference to user'
      t.references  :schema,                      null: false,              comment: 'Reference to schema'
      t.string      :info,          limit: 1000,  null: true,               comment: 'Additional info'
      t.integer     :lock_version,                null: false,  default: 0, comment: 'Version for optimistic locking'
      t.timestamps
    end
  end

end
