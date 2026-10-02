# frozen_string_literal: true
require_relative 'lib/body_limit'
require_relative 'lib/database'
require_relative 'lib/store'
require_relative 'app'

InspectionLog::App.set :store, InspectionLog::Store.new(InspectionLog::Database.connect)
use InspectionLog::BodyLimit
run InspectionLog::App
