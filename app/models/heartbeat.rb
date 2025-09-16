require 'socket'

class Heartbeat < ApplicationRecord
  @@ip_address = nil
  @@known_concurrent_instances = {}                                             # Check for known concurrent instances to avoid repeated warnings

  # Create or update the heartbeat record for the current server instance
  # Uses hostname and IP address to identify the server instance
  # Updates the heartbeat timestamp to the current time
  # Raises an error if unable to determine the IP address from the database
  # @return [void]
  def self.record_heartbeat
    heartbeat = Heartbeat.find_or_initialize_by(hostname: Socket.gethostname, ip_address: current_ip_address)
    heartbeat.heartbeat_ts = Time.current
    heartbeat.save!
  end

  def self.check_for_concurrent_instance
    # Raise exception if there are other heartbeat records within the last 5 minutes
    others = execute_check_sql(2.minutes.ago)
    if !others.empty?
      msg = "Foreign heartbeat record found younger than 2 minutes for this DB schema other than (#{Socket.gethostname}/#{current_ip_address}): #{others.map { |h| "#{h.hostname}/#{h.ip_address} (last heartbeat at #{h.heartbeat_ts})" }.join(', ')}!\n" +
            " Only one server instance is allowed to run with the same DB schema at a time!\n"+
            "This might be a false positive if the instance was recreated in a new Docker container."
      Rails.logger.error("Heartbeat.check_for_concurrent_instance") { msg }
    end

    # Log error if there are other heartbeat records within the last 24 hours, log only one time if the heartbeat timestamp does not change
    # This should catch possible timezone issues where the other heartbeat record is older than 5 minutes but still from the same day
    # This is just a warning and does not raise an exception, because it might be a false positive if the instance was moved to another server
    others = execute_check_sql(24.hours.ago)
    if !others.empty?
      others.each do |o|
        key = "#{o.hostname}/#{o.ip_address}"
        if !(@@known_concurrent_instances.key?(key) && @@known_concurrent_instances[key] == o.heartbeat_ts)
          @@known_concurrent_instances[key] = o.heartbeat_ts                    # Remenber the known concurrent instance to avoid repeated warnings
          msg = "Foreign heartbeat records of the last 24 hours found for this DB schema other than (#{Socket.gethostname}/#{current_ip_address}): #{o.hostname}/#{o.ip_address} (last heartbeat at #{o.heartbeat_ts})!\n" +
                "Only one server instance is allowed to run with the same DB schema at a time!\n" +
                "This might be a false positive if the instance was recreated in a new Docker container."
          Rails.logger.warn("Heartbeat.check_for_concurrent_instance") { msg }
        end
      end
    end
  end

  # Get the IP address of the current database session
  # Cache the value in a class variable to avoid repeated queries
  # @return [String] IP address
  def self.current_ip_address
    if @@ip_address.nil?
      @@ip_address = case MovexCdc::Application.config.db_type
                     when 'ORACLE' then
                       addresses    = Heartbeat.find_by_sql("SELECT SYS_CONTEXT('USERENV', 'IP_ADDRESS') address from DUAL")
                       raise "Unable to determine IP address from database" if addresses.empty?
                       addresses.first.address
                     else
                       "Dummy"
                     end
    end
    @@ip_address
  end

  # Execute the SQL using bind variables instead of string interpolation to avoid SQL injection
  # @param [Time] time_limit maximum execution time in seconds
  # @return [Array<Hash>] result set as array of hashes
  def self.execute_check_sql(time_limit)
    Database.select_all("SELECT * FROM Heartbeats WHERE (HostName != :hostname OR IP_Address != :ip_address) AND Heartbeat_TS > :time_limit",
                        {
                          hostname: Socket.gethostname,
                          ip_address: current_ip_address,
                          time_limit: time_limit
                        }
    )
  end
end
