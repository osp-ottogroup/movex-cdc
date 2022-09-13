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

  create_table "VICTIM1", primary_key: ["ID", "Num_Val", "Name", "Date_Val", "TS_Val", "Raw_Val"], force: :cascade do |t|
    t.decimal "ID"
    t.decimal "Num_Val"
    t.string "Name", limit: 20
    t.string "CHAR_NAME", limit: 1
    t.datetime "Date_Val"
    t.datetime "TS_Val", precision: 6
    t.binary "Raw_Val"
    t.datetime "TSTZ_Val", precision: 6
    t.text "RowID_Val"
  end

  create_table "VICTIM2", primary_key: "ID", id: :decimal, force: :cascade do |t|
    t.text "Large_Text"
  end

  create_table "VICTIM3", primary_key: "ID", id: :decimal, force: :cascade do |t|
    t.string "Name", limit: 20
  end

  create_table "activity_logs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "schema_name", limit: 256
    t.string "table_name", limit: 256
    t.string "column_name", limit: 256
    t.string "action", limit: 1024, null: false
    t.string "client_ip", limit: 40
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_name", "table_name", "column_name"], name: "IX_ACTIVITY_LOG_TABCOL"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "columns", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "name", limit: 256, null: false
    t.string "info", limit: 1000
    t.string "yn_log_insert", limit: 1, default: "N", null: false
    t.string "yn_log_update", limit: 1, default: "N", null: false
    t.string "yn_log_delete", limit: 1, default: "N", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "name"], name: "IX_COLUMNS_TABLE_NAME", unique: true
    t.index ["table_id"], name: "index_columns_on_table_id"
  end

  create_table "conditions", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "filter", limit: 4000, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "operation"], name: "IX_CONDITIONS_TABLE_ID_OPER", unique: true
    t.index ["table_id"], name: "index_conditions_on_table_id"
  end

  create_table "event_log_final_errors", force: :cascade do |t|
    t.bigint "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.string "msg_key", limit: 4000
    t.datetime "created_at", null: false
    t.datetime "error_time", null: false
    t.text "error_msg", null: false
    t.string "transaction_id", limit: 100
    t.index ["table_id"], name: "index_event_log_final_errors_on_table_id"
  end

  create_table "event_logs", force: :cascade do |t|
    t.bigint "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.string "msg_key", limit: 4000
    t.datetime "created_at", null: false
    t.datetime "last_error_time"
    t.integer "retry_count", default: 0, null: false
    t.string "transaction_id", limit: 100
    t.index ["table_id"], name: "index_event_logs_on_table_id"
  end

  create_table "schema_rights", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "schema_id", null: false
    t.string "info", limit: 1000
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "yn_deployment_granted", limit: 1, default: "N", null: false
    t.index ["schema_id"], name: "index_schema_rights_on_schema_id"
    t.index ["user_id", "schema_id"], name: "IX_SCHEMA_RIGHTS_LOGICAL_PKEY", unique: true
    t.index ["user_id"], name: "index_schema_rights_on_user_id"
  end

  create_table "schemas", force: :cascade do |t|
    t.string "name", limit: 256, null: false
    t.string "topic", limit: 255
    t.datetime "last_trigger_deployment"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "IX_SCHEMAS_NAME", unique: true
  end

  create_table "statistics", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.integer "events_success", null: false
    t.datetime "end_timestamp", null: false
    t.integer "events_delayed_errors", default: 0, null: false
    t.integer "events_final_errors", default: 0, null: false
    t.integer "events_d_and_c_retries", default: 0, null: false
    t.integer "events_delayed_retries", default: 0, null: false
    t.index ["end_timestamp", "table_id", "operation"], name: "IX_STATISTICS_TS_TABLE_ID_OPER"
    t.index ["table_id"], name: "index_statistics_on_table_id"
  end

  create_table "tables", force: :cascade do |t|
    t.integer "schema_id", null: false
    t.string "name", limit: 256, null: false
    t.string "info", limit: 1000
    t.string "topic", limit: 255
    t.string "kafka_key_handling", limit: 1, default: "N", null: false
    t.string "fixed_message_key", limit: 4000
    t.string "yn_hidden", limit: 1, default: "N", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "yn_record_txid", limit: 1, default: "N", null: false
    t.string "yn_initialization", limit: 1, default: "N", null: false
    t.string "initialization_filter", limit: 4000
    t.string "initialization_order_by", limit: 4000
    t.string "yn_initialize_with_flashback", limit: 1, default: "Y", null: false
    t.index ["schema_id", "name"], name: "IX_TABLES_SCHEMA_NAME", unique: true
    t.index ["schema_id"], name: "index_tables_on_schema_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", limit: 256, null: false
    t.string "db_user", limit: 128
    t.string "first_name", limit: 128, null: false
    t.string "last_name", limit: 128, null: false
    t.string "yn_admin", limit: 1, default: "N", null: false
    t.string "yn_account_locked", limit: 1, default: "N", null: false
    t.integer "failed_logons", limit: 2, default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "yn_hidden", limit: 1, default: "N", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["db_user"], name: "IX_USERS_DB_USER"
    t.index ["email"], name: "IX_USERS_EMAIL", unique: true
  end

  add_foreign_key "activity_logs", "users"
  add_foreign_key "columns", "tables"
  add_foreign_key "conditions", "tables"
  add_foreign_key "schema_rights", "schemas", on_delete: :cascade
  add_foreign_key "schema_rights", "users", on_delete: :cascade
  add_foreign_key "tables", "schemas"
end
