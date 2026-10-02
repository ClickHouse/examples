# frozen_string_literal: true
require_relative 'inputs'

module InspectionLog
  class Store
    CAPACITY = 200
    HISTORY_LIMIT = 25
    EXPORT_LIMIT = 100

    def initialize(db)
      @db = db
      @assets = db[Sequel.qualify(:inspection_api, :assets)]
      @budget = db[Sequel.qualify(:inspection_api, :fixture_budget)]
      @inspections = db[Sequel.qualify(:inspection_api, :inspections)]
      @results = db[Sequel.qualify(:inspection_api, :inspection_results)]
    end

    def assets = @assets.order(:id).all

    def save(input)
      @db.transaction do
        budget = @budget.where(id: 1).for_update.first
        raise 'Missing seeded fixture budget' unless budget
        retained = @inspections.where(request_id: input.fetch(:request_id)).first
        if retained
          raise Conflict, 'Request ID already belongs to different content' unless retained[:digest] == input.fetch(:digest)
          next retained[:id]
        end
        raise CapacityReached, 'This sample fixture has reached 200 inspections' if budget[:used] >= CAPACITY
        raise InvalidInput, 'Unknown synthetic asset' unless @assets.where(id: input.fetch(:asset_id)).first
        slot = budget[:used] + 1
        @budget.where(id: 1).update(used: slot)
        @inspections.insert(id: slot, request_id: input.fetch(:request_id), digest: input.fetch(:digest),
          asset_id: input.fetch(:asset_id), inspected_on: input.fetch(:inspected_on),
          outcome: input.fetch(:outcome), note: input.fetch(:note))
        Inputs::CHECKS.each do |name|
          @results.insert(inspection_id: slot, check_name: name, result: input.fetch(:checklist).fetch(name))
        end
        slot
      end
    end

    def inspection(id)
      header = @inspections.where(id: id).first
      return nil unless header
      header.merge(checklist: @results.where(inspection_id: id).order(:check_name).to_hash(:check_name, :result))
    end

    def filtered(filter)
      query = @inspections.where(asset_id: filter.fetch(:asset_id), inspected_on: filter.fetch(:first)..filter.fetch(:last))
      filter.fetch(:outcome).empty? ? query : query.where(outcome: filter.fetch(:outcome))
    end

    def history(filter)
      filtered(filter).order(Sequel.desc(:inspected_on), Sequel.desc(:id)).limit(HISTORY_LIMIT).all
    end

    def export_rows(filter)
      headers = filtered(filter).order(:inspected_on, :id).limit(EXPORT_LIMIT + 1).all
      raise ExportTooLarge, 'More than 100 rows match; narrow the date or outcome filter' if headers.length > EXPORT_LIMIT
      return [] if headers.empty?
      # Each dataset call releases its pool checkout before CSV generation or response delivery.
      checks = @results.where(inspection_id: headers.map { |row| row[:id] }).all.group_by { |row| row[:inspection_id] }
      names = assets.to_h { |asset| [asset[:id], asset[:name]] }
      headers.map do |header|
        header.merge(asset_name: names.fetch(header[:asset_id]),
          checklist: checks.fetch(header[:id]).to_h { |row| [row[:check_name], row[:result]] })
      end
    end
  end
end
