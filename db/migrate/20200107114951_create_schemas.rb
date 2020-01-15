class CreateSchemas < ActiveRecord::Migration[6.0]
  def change
    create_table :schemas, comment: 'Schemas allowed for use with TriXX by admin acount' do |t|
      t.string :name, limit: 256, null: false,  comment: 'Name of corresponding database schema'
      t.timestamps
    end
  end
end
