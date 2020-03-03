# Base class for models without DB table but using ActiveRecord::Base
class TableLess

  def self.select_all(sql, filter = {})
    raise "Hash expected as filter" if filter.class != Hash

    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    ActiveRecord::Base.connection.select_all(sql, 'TableLess.select_all', binds)
  rescue Exception => e
    Rails.logger.error "#{e.class}: #{e.message}\nErroneous SQL:\n#{sql}"
    raise e
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

  def self.execute(sql, filter = {})
    raise "Hash expected as filter" if filter.class != Hash

    binds = []
    filter.each do |key, value|
      binds << ActiveRecord::Relation::QueryAttribute.new(key, value, ActiveRecord::Type::Value.new)
    end

    ActiveRecord::Base.connection.exec_update(sql, 'TableLess.execute', binds)  # returns the number of affected rows
  rescue Exception => e
    Rails.logger.error "#{e.class}: #{e.message}\nErroneous SQL:\n#{sql}"
    raise e
  end

end