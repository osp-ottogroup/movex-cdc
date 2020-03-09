source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# According to JRuby-Version
# jruby-9.2.0.8: 2.5.3
# jruby-9.2.0.9: 2.5.7
ruby '2.5.3'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '6.0.2.1'
# Use jdbcsqlite3 as the database for Active Record
gem 'activerecord-jdbcsqlite3-adapter'
gem 'activerecord-oracle_enhanced-adapter'

# Use Puma as the app server
gem 'puma', '~> 4.1'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'

# Use Json Web Token (JWT) for token based authentication
gem 'jwt'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'

gem 'ruby-kafka'

# Use Active Storage variant
# gem 'image_processing', '~> 1.2'

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'

group :development do
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'rubocop'
end

group :test do
  gem 'simplecov', require: false
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
