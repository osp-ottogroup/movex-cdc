class CreateSchemaRights < ActiveRecord::Migration[6.0]

  def change
    create_table :schema_rights do |t|
      t.references  :user,           null: false,  comment: 'Reference to user'
      t.references  :schema,         null: false,  comment: 'Reference to schema'
      t.string      :info, limit: 1000,  null: false,  comment: 'Additional info'
      t.timestamps
    end
  end

end
