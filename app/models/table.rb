class Table < ApplicationRecord
  belongs_to  :schema
  has_many    :columns
  has_many    :conditions
  validate    :topic_in_table_or_schema
  validate    :kafka_key_handling_validate

  def topic_in_table_or_schema
    if (topic.nil? || topic == '') && (schema.topic.nil? || schema.topic == '')
      errors.add(:topic, "cannot be empty if topic of schema is also empty")
    end
  end

  def kafka_key_handling_validate
    valid_kafka_key_handlings = ['N', 'P', 'F']
    unless valid_kafka_key_handlings.include? kafka_key_handling
      errors.add(:kafka_key_handling, "Invalid value '#{kafka_key_handling}', valid values are #{valid_kafka_key_handlings}")
    end

    if kafka_key_handling != 'F' && !(fixed_message_key.nil? || fixed_message_key == '')
      errors.add(:fixed_message_key, "Fixed message key must be empty if Kafka key handling is not 'F' (Fixed)")
    end

    if kafka_key_handling == 'F' && (fixed_message_key.nil? || fixed_message_key == '')
      errors.add(:fixed_message_key, "Fixed message key must not be empty if Kafka key handling is 'F' (Fixed)")
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
