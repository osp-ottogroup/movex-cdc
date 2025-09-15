class ColumnExpressionsFk < ActiveRecord::Migration[6.0]
  def change
    add_foreign_key :column_expressions, :tables, name: 'fk_column_expressions_table', index: { name: 'FK_COLUMN_EXPRESSIONS_TABLE' }
  end
end

