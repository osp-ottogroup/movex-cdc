module KeyHelper
  def self.long_operation_from_short(short_op)
    case short_op
    when 'i' then 'INIT'                                                        # initial load of table content to Kafka
    when 'I' then 'INSERT'
    when 'U' then 'UPDATE'
    when 'D' then 'DELETE'
    else raise "Unknown short operation '#{short_op}'"
    end
  end

  def self.log_level_as_string
    result = case Rails.logger.level
             when 0 then 'DEBUG'
             when 1 then 'INFO'
             when 2 then 'WARN'
             when 3 then 'ERROR'
             when 4 then 'FATAL'
             when 5 then 'UNKNOWN'
             else '[Unsupported]'
             end
    result
  end


end
