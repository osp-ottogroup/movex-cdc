require 'socket'

class Heartbeat < ApplicationRecord
  @@ip_address = nil

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
    others = Heartbeat.where("(HostName != ? OR IP_Address != ?) AND Heartbeat_TS > ?", Socket.gethostname, current_ip_address, 5.minutes.ago)
    if !others.empty?
      msg = "Foreign heartbeat records found for this DB schema other than (#{Socket.gethostname}/#{current_ip_address}): #{others.map { |h| "#{h.hostname}/#{h.ip_address} (last heartbeat at #{h.heartbeat_ts})" }.join(', ')}! Only one server instance is allowed to run with the same DB schema at a time!"
      Rails.logger.error("Heartbeat.check_for_concurrent_instance") { msg }
      raise msg
    end

    # Log error if there are other heartbeat records within the last 24 hours
    # This should catch possible timezone issues where the other heartbeat record is older than 5 minutes but still from the same day
    # This is just a warning and does not raise an exception, because it might be a false positive if the instance was moved to another server
    others = Heartbeat.where("(HostName != ? OR IP_Address != ?) AND Heartbeat_TS > ?", Socket.gethostname, current_ip_address, 24.hours.ago)
    if !others.empty?
      msg = "Foreign heartbeat records of the last 24 hours found for this DB schema other than (#{Socket.gethostname}/#{current_ip_address}): #{others.map { |h| "#{h.hostname}/#{h.ip_address} (last heartbeat at #{h.heartbeat_ts})" }.join(', ')}! " +
            "Only one server instance is allowed to run with the same DB schema at a time! " +
            "This might be a false positive if the instance was recreated in a new Docker container."
      Rails.logger.warn("Heartbeat.check_for_concurrent_instance") { msg }
    end

  end

  # Get the IP address of the current database session
  # Cache the value in a class variable to avoid repeated queries
  # @return [String] IP address
  def self.current_ip_address
    if @@ip_address.nil?
      addresses    = Heartbeat.find_by_sql("SELECT SYS_CONTEXT('USERENV', 'IP_ADDRESS') address from DUAL")
      raise "Unable to determine IP address from database" if addresses.empty?
      @@ip_address = addresses.first.address
    end
    @@ip_address
  end
end
