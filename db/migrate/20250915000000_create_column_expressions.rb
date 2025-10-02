class CreateColumnExpressions < ActiveRecord::Migration[6.0]
  def change
    create_table :column_expressions do |t|
      t.references  :table,           null: false,  index: { name: "FK_COLUMN_EXPRESSIONS_TABLE"}, comment: 'Reference to table'
      t.string      :operation,       limit: 1,     null: false,              comment: 'Type of operation: I=insert, U=update, D=delete'
      t.text        :sql,                           null: false,              comment: 'SELECT expression extension of column list'
      t.integer     :lock_version,                  null: false,  default: 0, comment: 'Version for optimistic locking'
      t.timestamps
    end
  end
end
