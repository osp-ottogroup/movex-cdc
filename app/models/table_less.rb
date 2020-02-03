# Base class for models without DB table but using ActiveRecord::Base
class TableLess

  def self.select_all(sql, filter = {})
    raise "Hash expected as filter" if filter.class != Hash
    ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.send(:sanitize_sql_array, [sql, filter])
    )
  end

  def self.select_first_row(sql, filter = {})
    result = select_all(sql, filter)
    return nil if result.count == 0
    result[0]
  end

  def self.select_one(sql, filter = {})
    result = select_first_row(sql, filter)
    return nil if result.nil?
    result.first[1]                                                             # Value of Key/Value-Tupels of first element
  end

end