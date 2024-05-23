class EncryptionKeyVersionsCreation < ActiveRecord::Migration[6.0]
  def change
    create_table :encryption_key_versions, comment: 'Encryption key versions with values' do |t|
      t.references  :encryption_key,          null: false,  comment: 'Reference to encryption key'
      t.integer     :version_no, precision: 16,           null: false,  comment: 'Version number of encryption key. The key with Start_time < now and the highest version number is the active key'
      t.timestamp   :start_time,                          null: false,  comment: 'Start time of key version to be used. Must be equal or higher than the start time of the previous version'
      t.text        :encryption_key_base64,               null: false,  comment: 'The encryption key as base64 encoded string'
    end
  end
end
