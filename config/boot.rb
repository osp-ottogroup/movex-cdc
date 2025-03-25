ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.

# Fix concurrent-ruby removing logger dependency which Rails itself does not have
# Error: NameError: uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger
# See https://stackoverflow.com/questions/79360526/uninitialized-constant-activesupportloggerthreadsafelevellogger-nameerror
require "logger"

# require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Workaround to avoid the error: undefined field 'map' for class 'Java::OrgJruby::RubyObjectSpace::WeakMap'
# with oracle-enhanced-adapter 6.1.6 and JRuby 9.4.6.0 and following versions
# Prevent execution of the code block in the if statement by comparing RUBY_ENGINE with a not existing value
# This patches the gem each time it is installed again
# Peter Ramm, 2024-06-18
# See also: https://github.com/rsim/oracle-enhanced/pull/2360

gem_path = Gem::Specification.find_by_name('activerecord-oracle_enhanced-adapter').gem_dir
file_path = File.join(gem_path, 'lib', 'active_record', 'connection_adapters', 'oracle_enhanced_adapter.rb')
content = File.read(file_path)
new_content = content.gsub("if RUBY_ENGINE == \"jruby\"", "if RUBY_ENGINE == \"xjruby\"")
File.open(file_path, 'w') { |file| file.write(new_content) }
