Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = false
  config.cache_store = :memory_store, { size: 16.megabytes }
  config.force_ssl = true
  config.hosts = ENV.fetch("APP_HOSTS").split(",")
  config.log_level = :info
  config.public_file_server.enabled = true
end
