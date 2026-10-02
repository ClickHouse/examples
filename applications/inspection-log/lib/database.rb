# frozen_string_literal: true
require 'sequel'
require 'pg'

module InspectionLog
  module Database
    module_function

    def connect(migration: false)
      host = ENV.fetch('PGHOST')
      raise ArgumentError, 'Use one DNS hostname or IPv4 address' unless host.match?(/\A[A-Za-z0-9.-]+\z/)
      port = Integer(ENV.fetch('PGPORT', '5432'), 10)
      raise ArgumentError, 'Invalid port' unless (1..65_535).cover?(port)
      user = migration ? 'inspection_migrator' : 'inspection_app'
      password = ENV.fetch(migration ? 'MIGRATOR_PASSWORD' : 'PGPASSWORD')
      Sequel.default_timezone = :utc
      db = Sequel.connect(adapter: 'postgres', host: host, port: port,
        database: ENV.fetch('PGDATABASE', 'postgres'), user: user, password: password,
        sslmode: 'verify-full', sslrootcert: ENV.fetch('PGSSLROOTCERT'),
        connect_timeout: 5, max_connections: migration ? 1 : 4, pool_timeout: 3,
        after_connect: lambda { |connection|
          connection.exec('SET ROLE inspection_owner') if migration
          connection.exec('SET search_path TO inspection_api, pg_catalog')
          connection.exec("SET statement_timeout TO '#{migration ? 15 : 8}s'")
          connection.exec("SET lock_timeout TO '3s'")
          connection.exec("SET idle_in_transaction_session_timeout TO '10s'")
        })
      db.extension(:pg_auto_parameterize) unless migration
      db
    end
  end
end
