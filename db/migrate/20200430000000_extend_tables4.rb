class ExtendTables4 < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :kafka_key_handling, :string, limit: 1, null: false, default: 'N', comment: 'Type of Kafka key handling for this table. Valid values: N=none, P=primary key, F=fixed value'
  end
end

