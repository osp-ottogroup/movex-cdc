module ExceptionHelper
  def self.log_exception_backtrace(exception, line_number_limit=nil)
    curr_line_no=0
    output = ''
    exception.backtrace.each do |bt|
      output << "#{bt}\n" if line_number_limit.nil? || curr_line_no < line_number_limit # report First x lines of stacktrace in log
      curr_line_no += 1
    end

    Rails.logger.error "Stack-Trace for exception: #{exception.class} #{exception.message}\n#{output}"
  end

  def self.log_exception(exception, context)
    Rails.logger.error "#{self.class}: #{exception.class}: #{exception.message}"
    explanation = explain_exception(exception)
    Rails.logger.error explanation if explanation
    Rails.logger.error "Context: #{context}"
    if Rails.logger.level == 0 # DEBUG
      mem_info = memory_info_string
      Rails.logger.error mem_info if mem_info && mem_info != ''
      log_exception_backtrace(exception)
    else
      Rails.logger.error "Switch log level to 'debug' to get additional stack trace and memory info for exceptions!"
    end
  end


  def self.memory_info_string
    output = ''
    memory_info_hash.each do |key, value|
      output << "#{key} = #{value}, " unless value.nil?
    end
    output
  end

  # get Hash with details
  def self.memory_info_hash
    {
        'Total Memory (GB)': gb_value_from_proc('MemTotal',   'hw.memsize',),
        'Free Memory (GB)':  gb_value_from_proc('MemFree',    'page_free_count'),
        'Total Swap (GB)':   gb_value_from_proc('SwapTotal',  'vm.swapusage'),
        'Free Swap (GB)':    gb_value_from_proc('SwapFree',   'vm.swapusage')
    }
  end

  private
  def self.gb_value_from_proc(key_linux, key_darwin)
    retval = nil
    case RbConfig::CONFIG['host_os']
    when 'linux' then
      cmd = "cat /proc/meminfo 2>/dev/null | grep #{key_linux}"
      output = %x[ #{cmd} ]
      retval = (output.split(' ')[1].to_f/(1024*1024)).round(3) if output[key_linux]
    when 'darwin' then
      cmd = "sysctl -a | grep '#{key_darwin}'"
      output = %x[ #{cmd} ]
      if output[key_darwin]                                                     # anything found?
        if key_darwin == 'vm.swapusage'
          case key_linux
          when 'SwapTotal' then
            retval = (output.split(' ')[3].to_f / 1024).round(3)
          when 'SwapFree' then
            retval = (output.split(' ')[9].to_f / 1024).round(3)
          end
        else
          page_multitplier = 1                                                       # bytes
          page_multitplier= 4096 if output['vm.page']                                # pages
          retval = (output.split(' ')[1].to_f * page_multitplier / (1024*1024*1024)).round(3)
        end
      end
    end
    retval
  end

  # try to interpret what happened at Kafka
  def self.explain_exception(exception)
    case exception.class.name
    when 'Kafka::UnknownError' then
      case exception.message.strip
      when 'Unknown error with code 87' then 'Possible reason: Log compaction is activated for topic (log.cleanup.policy=compact) but events are created by TriXX without key'
      end
    end
  end

end

