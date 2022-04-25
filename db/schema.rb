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

ActiveRecord::Schema.define(version: 2022_04_14_000000) do

  create_table "activity_logs", force: :cascade do |t|
    t.integer "user_id", limit: 19, precision: 19, null: false, comment: "Reference to user"
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
    t.integer "table_id", limit: 19, precision: 19, null: false, comment: "Reference to table"
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
    t.integer "table_id", limit: 19, precision: 19, null: false, comment: "Reference to table"
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

