class ExtendTableKeyExpression < ActiveRecord::Migration[6.0]
  def change
    add_column :tables, :key_expression, :text, null: true, comment: 'SQL expression or statement that defines the message key'
  end
end