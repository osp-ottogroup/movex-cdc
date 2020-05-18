# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_05_04_100000) do

  create_table "activity_logs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "schema_name", limit: 256
    t.string "table_name", limit: 256
    t.string "column_name", limit: 256
    t.string "action", limit: 1024, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_name", "table_name", "column_name"], name: "IX_ACTIVITY_LOG_TABCOL"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "columns", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "name", limit: 256, null: false
    t.string "info", limit: 1000
    t.string "yn_log_insert", limit: 1, null: false
    t.string "yn_log_update", limit: 1, null: false
    t.string "yn_log_delete", limit: 1, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "name"], name: "IX_COLUMNS_TABLE_NAME", unique: true
    t.index ["table_id"], name: "index_columns_on_table_id"
  end

  create_table "conditions", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "filter", limit: 4000, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "operation"], name: "IX_CONDITIONS_TABLE_ID_OPER", unique: true
    t.index ["table_id"], name: "index_conditions_on_table_id"
  end

  create_table "event_logs", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "operation", limit: 1, null: false
    t.string "dbuser", limit: 128, null: false
    t.text "payload", null: false
    t.datetime "created_at", null: false
    t.string "key", limit: 4000
    t.string "msg_key", limit: 4000
    t.index ["table_id"], name: "index_event_logs_on_table_id"
  end

  create_table "schema_rights", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "schema_id", null: false
    t.string "info", limit: 1000
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_id"], name: "index_schema_rights_on_schema_id"
    t.index ["user_id", "schema_id"], name: "IX_SCHEMA_RIGHTS_LOGICAL_PKEY", unique: true
    t.index ["user_id"], name: "index_schema_rights_on_user_id"
  end

  create_table "schemas", force: :cascade do |t|
    t.string "name", limit: 256, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "topic", limit: 255
    t.datetime "last_trigger_deployment"
    t.index ["name"], name: "IX_SCHEMAS_NAME", unique: true
  end

  create_table "semaphores", force: :cascade do |t|
    t.string "process_identifier", limit: 300, null: false
    t.integer "thread_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "tables", force: :cascade do |t|
    t.integer "schema_id", null: false
    t.string "name", limit: 256, null: false
    t.string "info", limit: 1000
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "topic", limit: 255
    t.string "kafka_key_handling", limit: 1, default: "N", null: false
    t.string "fixed_message_key", limit: 255
    t.index ["schema_id", "name"], name: "IX_TABLES_SCHEMA_NAME", unique: true
    t.index ["schema_id"], name: "index_tables_on_schema_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", limit: 256, null: false
    t.string "db_user", limit: 128
    t.string "first_name", limit: 128, null: false
    t.string "last_name", limit: 128, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "yn_admin", limit: 1, default: "N", null: false
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
