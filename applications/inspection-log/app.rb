# frozen_string_literal: true
require 'sinatra/base'
require 'rack/protection/authenticity_token'
require 'securerandom'
require 'time'
require 'sequel'
require_relative 'lib/body_limit'
require_relative 'lib/inputs'
require_relative 'lib/report'

module InspectionLog
  class App < Sinatra::Base
    secret = ENV.fetch('SESSION_SECRET')
    raise ArgumentError, 'Configure a private 128-character hex session secret' unless secret.match?(/\A[0-9a-f]{128}\z/)
    set :environment, :production
    set :sessions, {secret: secret, key: 'inspection.session', httponly: true,
                    same_site: :strict, secure: false, expire_after: 3600}
    set :host_authorization, {permitted_hosts: ['localhost', '127.0.0.1']}
    set :show_exceptions, false
    set :raise_errors, false
    set :logging, true
    set :static, true
    set :public_folder, File.expand_path('public', __dir__)
    set :views, File.expand_path('views', __dir__)
    set :store, nil
    use Rack::Protection::AuthenticityToken

    helpers do
      def h(value) = Rack::Utils.escape_html(value.to_s)
      def csrf = Rack::Protection::AuthenticityToken.token(session)
      def selected(actual, expected) = actual.to_s == expected.to_s ? 'selected' : ''
      def store = settings.store
      def assets = (@assets ||= store.assets)
      def defaults
        {'request_id' => SecureRandom.uuid, 'asset_id' => '1', 'inspected_on' => Date.today.iso8601,
         'outcome' => 'pass', 'housing' => 'ok', 'cable' => 'ok', 'label' => 'ok', 'note' => ''}
      end
      def default_filter
        {'asset_id' => '1', 'from' => (Date.today - 30).iso8601, 'to' => Date.today.iso8601, 'outcome' => ''}
      end
      def form_error(status_code, message)
        @error = message
        status status_code
        erb :form
      end
    end

    before do
      headers 'Cache-Control' => 'no-store'
      halt 400, 'Query is too large' if request.query_string.bytesize > 2048
      if request.request_method == 'POST'
        allowed = ['http://127.0.0.1:9292', 'http://localhost:9292']
        halt 403, 'Origin not permitted' unless allowed.include?(request.env['HTTP_ORIGIN'])
        halt 400, 'Query parameters are not accepted on save' unless request.query_string.empty?
      end
    end

    get '/' do
      @fields = defaults
      assets
      erb :form
    end

    post '/inspections' do
      @fields = request.POST
      # Never echo invalid byte sequences or controls into an error page.
      begin
        @fields.each_value { |value| Inputs.text(value, BodyLimit::MAX_BYTES) }
      rescue InvalidInput
        halt 400, 'Malformed form text'
      end
      assets
      begin
        id = store.save(Inputs.form(@fields))
        redirect "/inspections/#{id}", 303
      rescue InvalidInput => error
        form_error(422, error.message)
      rescue Conflict => error
        form_error(409, error.message)
      rescue CapacityReached => error
        form_error(409, error.message)
      rescue Sequel::DatabaseError => error
        warn "Inspection save failed: #{error.class}: #{error.message}"
        form_error(503, 'Save could not be confirmed. Keep this request ID and retry the same fields.')
      end
    end

    get '/inspections/:id' do
      id = Inputs.integer(params.fetch('id'), 200)
      @inspection = store.inspection(id)
      halt 404, 'Inspection not found' unless @inspection
      @asset = assets.find { |asset| asset[:id] == @inspection[:asset_id] }
      erb :inspection
    rescue InvalidInput => error
      halt 400, h(error.message)
    end

    get '/history' do
      @filter_fields = request.GET.empty? ? default_filter : request.GET
      assets
      begin
        @history = store.history(Inputs.filters(@filter_fields))
      rescue InvalidInput => error
        @history = []
        @error = error.message
        status 422
      end
      erb :history
    end

    get '/report.csv' do
      @filter_fields = request.GET
      assets
      begin
        rows = store.export_rows(Inputs.filters(@filter_fields))
        content_type 'text/csv', charset: 'utf-8'
        attachment 'synthetic-inspections.csv'
        Report.csv(rows)
      rescue InvalidInput, ExportTooLarge => error
        @error = error.message
        @history = []
        status 422
        erb :history
      end
    end

    error do
      warn "Inspection request failed: #{env['sinatra.error'].class}"
      content_type 'text/plain', charset: 'utf-8'
      status 503
      'Records are temporarily unavailable. Try again after checking the service.'
    end
  end
end
