class ExtendColumnExpressionsInfo < ActiveRecord::Migration[6.0]
  def change
    add_column :column_expressions, :info, :string,  limit: 1000, null: true, comment: 'Additional info about the expression'
  end
end