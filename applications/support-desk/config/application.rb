require_relative "boot"
require "rails"
require "active_support/core_ext/integer/time"
require "active_support/core_ext/numeric/bytes"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
Bundler.require(*Rails.groups)

module SupportDesk
  class Application < Rails::Application
    config.load_defaults 8.1
    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
    config.time_zone = "UTC"
    config.filter_parameters += [:password, :password_confirmation]
    config.action_dispatch.cookies_same_site_protection = :lax
    config.session_store :cookie_store, key: "_support_desk_session", httponly: true,
      same_site: :lax, secure: ENV.fetch("COOKIE_SECURE", "1") == "1", expire_after: 12.hours
    config.action_controller.default_protect_from_forgery = true
    # Keep migrations authoritative. A dumped schema would try CREATE SCHEMA,
    # but this example intentionally reserves schema creation for bootstrap.
    config.active_record.dump_schema_after_migration = false
  end
end
