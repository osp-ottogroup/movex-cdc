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

ActiveRecord::Schema[8.0].define(version: 2025_08_12_100000) do
  create_table "VICTIM1", primary_key: ["ID", "Num_Val", "Name", "Date_Val", "TS_Val", "Raw_Val"], force: :cascade do |t|
    t.decimal "ID"
    t.decimal "Num_Val"
    t.string "Name", limit: 20
    t.string "CHAR_NAME", limit: 1
    t.datetime "Date_Val", precision: nil
    t.datetime "TS_Val"
    t.binary "Raw_Val"
    t.datetime "TSTZ_Val"
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
    t.text "action", null: false
    t.string "client_ip", limit: 40
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["schema_name", "table_name", "column_name"], name: "ix_activity_log_tabcol"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["table_id", "name"], name: "ix_columns_table_name", unique: true
    t.index ["table_id"], name: "index_columns_on_table_id"
  end

  create_table "conditions", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "filter", limit: 4000, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["table_id", "operation"], name: "IX_CONDITIONS_TABLE_ID_OPER", unique: true
    t.index ["table_id"], name: "index_conditions_on_table_id"
  end

  create_table "encryption_key_versions", force: :cascade do |t|
    t.integer "encryption_key_id", null: false
    t.integer "version_no", null: false
    t.datetime "start_time", precision: nil, null: false
    t.text "encryption_key_base64", null: false
    t.index ["encryption_key_id", "version_no"], name: "IX_ENCR_KEY_VERSIONS_UNIQUE", unique: true
    t.index ["encryption_key_id"], name: "index_encryption_key_versions_on_encryption_key_id"
  end

  create_table "encryption_keys", force: :cascade do |t|
    t.string "name", limit: 200, null: false
    t.index ["name"], name: "IX_ENCRYPTION_KEYS_NAME_UNIQUE", unique: true
  end

  create_table "event_log_final_errors", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.string "msg_key", limit: 4000
    t.datetime "created_at", precision: nil, null: false
    t.datetime "error_time", precision: nil, null: false
    t.text "error_msg", null: false
    t.string "transaction_id", limit: 100
    t.index ["table_id"], name: "index_event_log_final_errors_on_table_id"
  end

  create_table "event_logs", id: false, force: :cascade do |t|
    t.integer "id", limit: 18, null: false
    t.integer "table_id", limit: 18, null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.string "msg_key", limit: 4000
    t.datetime "created_at", null: false
    t.datetime "last_error_time"
    t.integer "retry_count", default: 0, null: false
    t.string "transaction_id", limit: 100
  end

  create_table "schema_rights", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "schema_id", null: false
    t.string "info", limit: 1000
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "yn_deployment_granted", limit: 1, default: "N", null: false
    t.index ["schema_id"], name: "index_schema_rights_on_schema_id"
    t.index ["user_id", "schema_id"], name: "ix_schema_rights_logical_pkey", unique: true
    t.index ["user_id"], name: "index_schema_rights_on_user_id"
  end

  create_table "schemas", force: :cascade do |t|
    t.string "name", limit: 256, null: false
    t.string "topic", limit: 255
    t.datetime "last_trigger_deployment", precision: nil
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "encryption_key_id"
    t.index ["encryption_key_id"], name: "index_schemas_on_encryption_key_id"
    t.index ["name"], name: "IX_SCHEMAS_NAME", unique: true
  end

  create_table "statistics", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.integer "events_success", null: false
    t.datetime "end_timestamp", precision: nil, null: false
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "yn_record_txid", limit: 1, default: "N", null: false
    t.string "yn_initialization", limit: 1, default: "N", null: false
    t.string "initialization_filter", limit: 4000
    t.string "initialization_order_by", limit: 4000
    t.integer "encryption_key_id"
    t.string "yn_initialize_with_flashback", limit: 1, default: "Y", null: false
    t.string "yn_add_cloudevents_header", limit: 1, default: "N", null: false
    t.index ["encryption_key_id"], name: "index_tables_on_encryption_key_id"
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
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["db_user"], name: "IX_USERS_DB_USER"
    t.index ["email"], name: "IX_USERS_EMAIL", unique: true
  end

  add_foreign_key "schemas", "encryption_keys"
  add_foreign_key "tables", "encryption_keys"
  add_foreign_key "tables", "schemas"
end
