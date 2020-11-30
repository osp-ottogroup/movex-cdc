class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # Ensure column contains Y or N
  # @param [Symbol] column_name column name to check
  def validate_yn_column(column_name)
    if send(column_name) != 'Y' && send(column_name) != 'N'
      errors.add(column_name, "Column '#{column_name}' should contain 'Y' or 'N' but not '#{send(column_name)}'")
    end
  end

end
