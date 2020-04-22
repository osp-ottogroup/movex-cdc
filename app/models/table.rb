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

  # get array of corresponding database trigger objects as hash if exist
  def db_triggers
    DbTrigger.find_all_by_table(id, schema.name, name)
  end

  # get oldest change date of existing trigger for every operation (I/U/D)
  # there may exist multiple triggers for one operation (BEFORE, AFTER etc.)
  def oldest_trigger_change_dates_per_operation
    oldest_change_dates = {}
    db_triggers.each do |t|
      if oldest_change_dates[t[:operation]].nil? || ( !t[:changed_at].nil? && t[:changed_at] < oldest_change_dates[t[:operation]] )
        oldest_change_dates[t[:operation]] = t[:changed_at]
      end
    end
    oldest_change_dates
  end

end
