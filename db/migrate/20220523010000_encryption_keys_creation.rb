class EncryptionKeysCreation < ActiveRecord::Migration[6.0]
  def change
    create_table :encryption_keys, comment: 'Encryption key name for assignment from schemas and tables' do |t|
      t.string      :name, limit: 200,  null: false,  comment: 'Name of encryption key as unique reference'
    end
  end
end
