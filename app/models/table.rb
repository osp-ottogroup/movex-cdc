class Table < ApplicationRecord
  belongs_to  :schema
  has_many    :columns
  has_many    :conditions
  validate    :topic_in_table_or_schema

  def topic_in_table_or_schema
    if (topic.nil? || topic == '') && (schema.topic.nil? || schema.topic == '')
      errors.add(:topic, "cannot be empty if topic of schema is also empty")
    end
  end

end
