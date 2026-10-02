# frozen_string_literal: true
bind 'tcp://127.0.0.1:9292'
threads 4, 4
workers 0
environment 'production'
rackup File.expand_path('config.ru', __dir__)
