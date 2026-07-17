# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in subpath_identity.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

gem "standard", "~> 1.3"

group :test do
  # For exercising ControllerHelpers against a real ActionController::Base
  # subclass rather than mocking Rails' controller stack by hand.
  gem "actionpack", ">= 7.0"
end
