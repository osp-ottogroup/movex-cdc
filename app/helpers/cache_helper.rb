module CacheHelper
  # Cache schema names for repeated usage, react fast enough on topic name changes
  def self.schema_cache(schema_id)
    Rails.cache.fetch("Schema_#{schema_id}", expires_in: 1.minutes) do
      Schema.find schema_id
    end
  end

# Cache tables for repeated usage, react fast enough on topic name changes
  def self.table_cache(table_id)
    Rails.cache.fetch("Table_#{table_id}", expires_in: 1.minutes) do
      Table.find table_id
    end
  end

end

