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

ActiveRecord::Schema.define(version: 2020_01_21_000000) do

  create_table "activity_logs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "schema_name", limit: 256
    t.string "table_name", limit: 256
    t.string "column_name", limit: 256
    t.string "action", limit: 1024, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_name", "table_name", "column_name"], name: "ix_activity_log_tabcol"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "columns", force: :cascade do |t|
    t.integer "table_id", null: false
    t.string "name", limit: 256, null: false
    t.string "info", limit: 1000, null: false
    t.string "yn_log_insert", limit: 1, null: false
    t.string "yn_log_update", limit: 1, null: false
    t.string "yn_log_delete", limit: 1, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["table_id", "name"], name: "ix_columns_table_name", unique: true
    t.index ["table_id"], name: "index_columns_on_table_id"
  end

  create_table "event_logs", force: :cascade do |t|
    t.integer "schema_id"
    t.integer "table_id"
    t.text "payload"
    t.datetime "created_at", precision: 6
  end

  create_table "schema_rights", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "schema_id", null: false
    t.string "info", limit: 1000, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_id"], name: "index_schema_rights_on_schema_id"
    t.index ["user_id", "schema_id"], name: "ix_schema_rights_logical_pkey", unique: true
    t.index ["user_id"], name: "index_schema_rights_on_user_id"
  end

  create_table "schemas", force: :cascade do |t|
    t.string "name", limit: 256, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "ix_schemas_name", unique: true
  end

  create_table "tables", force: :cascade do |t|
    t.integer "schema_id", null: false
    t.string "name", limit: 256, null: false
    t.string "info", limit: 1000, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schema_id", "name"], name: "ix_tables_schema_name", unique: true
    t.index ["schema_id"], name: "index_tables_on_schema_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", limit: 256, null: false
    t.string "db_user", limit: 128
    t.string "first_name", limit: 128, null: false
    t.string "last_name", limit: 128, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["db_user"], name: "ix_users_db_user"
    t.index ["email"], name: "ix_users_email", unique: true
  end

  add_foreign_key "activity_logs", "users"
  add_foreign_key "columns", "tables"
  add_foreign_key "schema_rights", "schemas", on_delete: :cascade
  add_foreign_key "schema_rights", "users", on_delete: :cascade
  add_foreign_key "tables", "schemas"
end
