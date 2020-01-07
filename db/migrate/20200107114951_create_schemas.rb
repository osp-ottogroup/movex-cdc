class CreateSchemas < ActiveRecord::Migration[6.0]
  def change
    create_table :schemas do |t|
      t.string :name, limit: 256, null: false
      t.timestamps
      t.index ['name'],        name: "ix_schemas_name",     unique: true
    end
  end
end
