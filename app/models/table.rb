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

  def topic_to_use
    if topic.nil? || topic == ''
      schema.topic
    else
      topic
    end
  end

  # get list of corresponding database trigger objects as hash if exist
  def db_triggers
    DbTrigger.find_all_by_table(id, schema.name, name)
  end

end
