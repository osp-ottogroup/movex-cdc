class Table < ApplicationRecord
  belongs_to  :schema
  has_many    :columns
  has_many    :conditions
  validate    :topic_in_table_or_schema
  validate    :kafka_key_handling_validate

  # get all tables for schema where the current user has SELECT grant
  def self.all_allowed_tables_for_schema(schema_id, db_user)
    schema = Schema.find schema_id
    Table.where({schema_id: schema_id, yn_hidden: 'N' })
        .where(["Name IN (SELECT Table_Name FROM Allowed_DB_Tables WHERE Owner = ? AND Grantee = ?)", schema.name, db_user])
  end

  def topic_in_table_or_schema
    if (topic.nil? || topic == '')
      errors.add(:topic, "cannot be empty if topic of schema is also empty") if (schema.topic.nil? || schema.topic == '')
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
    DbTrigger.find_all_by_table(schema_id, id, schema.name, name)
  end

  # get oldest change date of existing trigger for every operation (I/U/D)
  # there may exist multiple triggers for one operation (BEFORE, AFTER etc.)
  def youngest_trigger_change_dates_per_operation
    youngest_change_dates = {}
    db_triggers.each do |t|
      if youngest_change_dates[t[:operation]].nil? || ( !t[:changed_at].nil? && t[:changed_at] > youngest_change_dates[t[:operation]] )
        youngest_change_dates[t[:operation]] = t[:changed_at]
      end
    end
    youngest_change_dates
  end
end
