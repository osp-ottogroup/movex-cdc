# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2022_06_13_000000) do

  create_table "activity_logs", force: :cascade do |t|
    t.integer "user_id", precision: 38, null: false, comment: "Reference to user"
    t.string "schema_name", limit: 256, comment: "Name of schema"
    t.string "table_name", limit: 256, comment: "Name of table"
    t.string "column_name", limit: 256, comment: "Name of column"
    t.string "action", limit: 1024, null: false, comment: "Executed action / activity"
    t.string "client_ip", limit: 40, comment: "Client IP address for request"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_name", "table_name", "column_name"], name: "ix_activity_log_tabcol"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "columns", comment: "Columns with flags for DML operation to trigger", force: :cascade do |t|
    t.integer "table_id", precision: 38, null: false, comment: "Reference to table"
    t.string "name", limit: 256, null: false, comment: "Column name of database table"
    t.string "info", limit: 1000, comment: "Additional info"
    t.string "yn_log_insert", limit: 1, default: "N", null: false, comment: "Log this column at insert operation (Y/N)"
    t.string "yn_log_update", limit: 1, default: "N", null: false, comment: "Log this column at update operation (Y/N)"
    t.string "yn_log_delete", limit: 1, default: "N", null: false, comment: "Log this column at delete operation (Y/N)"
    t.integer "lock_version", precision: 38, default: 0, null: false, comment: "Version for optimistic locking"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "name"], name: "ix_columns_table_name", unique: true
    t.index ["table_id"], name: "index_columns_on_table_id"
  end

  create_table "conditions", force: :cascade do |t|
    t.integer "table_id", precision: 38, null: false, comment: "Reference to table"
    t.string "operation", limit: 1, null: false, comment: "Type of operation: I=insert, U=update, D=delete"
    t.string "filter", limit: 4000, null: false, comment: "Filter expression for WHEN-clause of trigger"
    t.integer "lock_version", precision: 38, default: 0, null: false, comment: "Version for optimistic locking"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "operation"], name: "ix_conditions_table_id_oper", unique: true
    t.index ["table_id"], name: "index_conditions_on_table_id"
  end

  create_table "event_log_final_errors", id: false, force: :cascade do |t|
    t.integer "id", limit: 18, precision: 18, null: false
    t.integer "table_id", limit: 18, precision: 18, null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.string "msg_key", limit: 4000
    t.datetime "created_at", precision: 6, null: false
    t.datetime "error_time", precision: 6, null: false
    t.text "error_msg", null: false
    t.string "transaction_id", limit: 100, comment: "Original database transaction ID (if recorded)"
  end

  create_table "event_logs", id: false, force: :cascade do |t|
    t.integer "id", limit: 18, precision: 18, null: false
    t.integer "table_id", limit: 18, precision: 18, null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.string "msg_key", limit: 4000
    t.datetime "created_at", precision: 6, null: false
    t.datetime "last_error_time", precision: 6, comment: "Last time processing resulted in error"
    t.integer "retry_count", precision: 38, default: 0, null: false, comment: "Number of processing retries after error"
    t.string "transaction_id", limit: 100, comment: "Original database transaction ID (if recorded)"
  end

  create_table "schema_rights", force: :cascade do |t|
    t.integer "user_id", precision: 38, null: false, comment: "Reference to user"
    t.integer "schema_id", precision: 38, null: false, comment: "Reference to schema"
    t.string "info", limit: 1000, comment: "Additional info"
    t.integer "lock_version", precision: 38, default: 0, null: false, comment: "Version for optimistic locking"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "yn_deployment_granted", limit: 1, default: "N", null: false, comment: "Is the user allowed to deploy triggers for this schema?"
    t.index ["schema_id"], name: "index_schema_rights_on_schema_id"
    t.index ["user_id", "schema_id"], name: "ix_schema_rights_logical_pkey", unique: true
    t.index ["user_id"], name: "index_schema_rights_on_user_id"
  end

  create_table "schemas", comment: "Schemas allowed for use with MOVEX CDC by admin acount", force: :cascade do |t|
    t.string "name", limit: 256, null: false, comment: "Name of corresponding database schema"
    t.string "topic", comment: "Default topic name for tables of this schema if no topic is defined at table level. Null if topic should be defined at table level"
    t.datetime "last_trigger_deployment", precision: 6, comment: "Timestamp of last successful trigger deployment for schema (no matter if there have been changes for triggers or not)"
    t.integer "lock_version", precision: 38, default: 0, null: false, comment: "Version for optimistic locking"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "ix_schemas_name", unique: true
  end

  create_table "statistics", comment: "Throughput statistics", force: :cascade do |t|
    t.integer "table_id", precision: 38, null: false, comment: "Reference to table"
    t.string "operation", limit: 1, null: false, comment: "Operation (I=Insert, U=Update, D=Delete)"
    t.integer "events_success", precision: 38, null: false, comment: "Number of successful processed events"
    t.datetime "end_timestamp", precision: 6, null: false, comment: "End of period where events are processed"
    t.integer "events_delayed_errors", precision: 38, default: 0, null: false, comment: "Number of erroneous single event processings ending in another retry after delay"
    t.integer "events_final_errors", precision: 38, default: 0, null: false, comment: "Number of erroneous single event processings ending in final error after retries"
    t.integer "events_d_and_c_retries", precision: 38, default: 0, null: false, comment: "Number of additional event processings due to divide&conquer retries"
    t.integer "events_delayed_retries", precision: 38, default: 0, null: false, comment: "Number of additional event processings due to delayed retries"
    t.index ["end_timestamp", "table_id", "operation"], name: "ix_statistics_ts_table_id_oper"
    t.index ["table_id"], name: "index_statistics_on_table_id"
  end

  create_table "tables", comment: "Tables planned for triger creation", force: :cascade do |t|
    t.integer "schema_id", precision: 38, null: false, comment: "Reference to schema"
    t.string "name", limit: 256, null: false, comment: "Table name of database table"
    t.string "info", limit: 1000, comment: "Additional info like responsible team"
    t.string "topic", comment: "Topic name for table. Topic name of schema is used s default if Null"
    t.string "kafka_key_handling", limit: 1, default: "N", null: false, comment: "Type of Kafka key handling for this table. Valid values: N=none, P=primary key, F=fixed value"
    t.string "fixed_message_key", limit: 4000, comment: "Fixed value for Kafka message key if kafka_key_handling=F"
    t.string "yn_hidden", limit: 1, default: "N", null: false, comment: "Is table hidden for GUI ? Tables are marked hidden instead of physical deletion."
    t.integer "lock_version", precision: 38, default: 0, null: false, comment: "Version for optimistic locking"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "yn_record_txid", limit: 1, default: "N", null: false, comment: "Record transaction-ID for events of this table?."
    t.string "yn_initialization", limit: 1, default: "N", null: false, comment: "Should current content of table be transferred to Kafka as insert events at next trigger generation?"
    t.string "initialization_filter", limit: 4000, comment: "SQL filter expression to filter current content of table before transferred to Kafka as insert events at next trigger generation"
    t.string "initialization_order_by", limit: 4000, comment: "Optionally sort current content of table before transferred to Kafka as insert events at next trigger generation"
    t.string "yn_initialize_with_flashback", limit: 1, default: "Y", null: false, comment: "Should flashback query used to init only records before create trigger SCN"
    t.index ["schema_id", "name"], name: "ix_tables_schema_name", unique: true
    t.index ["schema_id"], name: "index_tables_on_schema_id"
  end

  create_table "users", comment: "Users allowed to login", force: :cascade do |t|
    t.string "email", limit: 256, null: false, comment: "Uniqe identifier as login name"
    t.string "db_user", limit: 128, comment: "Database user used for authentication combined with password"
    t.string "first_name", limit: 128, null: false, comment: "First name of user"
    t.string "last_name", limit: 128, null: false, comment: "Last name of user"
    t.string "yn_admin", limit: 1, default: "N", null: false, comment: "Is user tagged as admin (Y/N)"
    t.string "yn_account_locked", limit: 1, default: "N", null: false, comment: "Is user account locked (Y/N)"
    t.integer "failed_logons", limit: 2, precision: 2, default: 0, null: false, comment: "Number of subsequent failed logons"
    t.integer "lock_version", precision: 38, default: 0, null: false, comment: "Version for optimistic locking"
    t.string "yn_hidden", limit: 1, default: "N", null: false, comment: "Is user hidden for GUI ? Users are marked hidden instead of physical deletion if they have dependencies."
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["db_user"], name: "ix_users_db_user"
    t.index ["email"], name: "ix_users_email", unique: true
  end

  add_foreign_key "activity_logs", "users", name: "fk_activity_logs_users"
  add_foreign_key "columns", "tables", name: "fk_columns_tables"
  add_foreign_key "conditions", "tables", name: "fk_conditions_tables"
  add_foreign_key "schema_rights", "schemas", name: "fk_schema_rights_schema", on_delete: :cascade
  add_foreign_key "schema_rights", "users", name: "fk_schema_rights_users", on_delete: :cascade
  add_foreign_key "tables", "schemas", name: "fk_tables_schema"
end
