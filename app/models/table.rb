class Table < ApplicationRecord
  belongs_to  :schema
  has_many    :columns
  has_many    :conditions

  # Tables that do not exist in database no more but are configured for TriXX
  attribute   :yn_deleted_in_db, :string, limit: 1, default: 'N'

  validate    :topic_in_table_or_schema
  validate    :kafka_key_handling_validate
  validate    :validate_yn_columns

  # get all tables for schema where the current user has SELECT grant
  def self.all_allowed_tables_for_schema(schema_id, db_user)
    schema = Schema.find schema_id
    #Table.where({schema_id: schema_id, yn_hidden: 'N' })
    #    .where(["Name IN (SELECT Table_Name FROM Allowed_DB_Tables WHERE Owner = ? AND Grantee = ?)", schema.name, db_user])

    # Find all tables where a user is allowed to read or do not exist no more
    Table.find_by_sql([ "SELECT t.*, CASE WHEN a.Table_Name IS NULL THEN 'Y' ELSE 'N' END YN_Deleted_In_DB
                         FROM   Tables t
                         LEFT OUTER JOIN Allowed_DB_Tables a ON a.Table_Name = t.Name AND a.Owner = :owner AND a.Grantee = :grantee
                         WHERE  t.Schema_ID = :schema_id
                         AND    t.YN_Hidden = 'N'
                        ", { owner: schema.name, grantee: db_user, schema_id: schema_id }
                      ]
    )
  end

  def topic_in_table_or_schema
    if (topic.nil? || topic == '')
      errors.add(:topic, "cannot be empty if topic of schema is also empty") if (schema.topic.nil? || schema.topic == '')
    end
  end

  def kafka_key_handling_validate
    valid_kafka_key_handlings = ['N', 'P', 'F', 'T']
    unless valid_kafka_key_handlings.include? kafka_key_handling
      errors.add(:kafka_key_handling, "Invalid value '#{kafka_key_handling}', valid values are #{valid_kafka_key_handlings}")
    end

    if kafka_key_handling != 'F' && !(fixed_message_key.nil? || fixed_message_key == '')
      errors.add(:fixed_message_key, "Fixed message key must be empty if Kafka key handling is not 'F' (Fixed)")
    end

    if kafka_key_handling == 'F' && (fixed_message_key.nil? || fixed_message_key == '')
      errors.add(:fixed_message_key, "Fixed message key must not be empty if Kafka key handling is 'F' (Fixed)")
    end

    if kafka_key_handling == 'T' && (yn_record_txid != 'Y')
      errors.add(:kafka_key_handling, "Kafka key handling 'T' (Transaction-ID) is not possible if transaction-ID is not recorded")
    end
  end

  def validate_yn_columns
    validate_yn_column :yn_record_txid
    validate_yn_column :yn_hidden
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
