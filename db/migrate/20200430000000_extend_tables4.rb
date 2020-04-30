class ExtendTables4 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :kafka_key_handling, :string, limit: 1, null: false, default: 'N', comment: 'Type of Kafka key handling for this table. Valid values: N=none, P=primary key, F=fixed value'
    add_column :tables, :fixed_message_key,  :string, limit: 255, null: true, comment: 'Fixed value for Kafka message key if kafka_key_handling=F'
  end
end

