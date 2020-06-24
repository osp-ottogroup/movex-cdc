class Schema < ApplicationRecord
  has_many :tables
  has_many :schema_rights
  validate    :topic_in_table_or_schema

  def topic_in_table_or_schema
    if topic.nil? || topic == ''
      tables.each do |table|
        errors.add(:topic, "cannot be empty if topic of any table of schema is also empty") if table.topic.nil? || table.topic == ''
      end
    end
  end

end
