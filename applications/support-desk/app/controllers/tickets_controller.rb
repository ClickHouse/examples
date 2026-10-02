class TicketsController < ApplicationController
  before_action :load_ticket, only: [:show, :claim, :close, :reopen]

  def index
    @page = page_number(:page)
    rows = visible_tickets.includes(:customer, :assignee).order(created_at: :desc, id: :desc)
      .offset((@page - 1) * 20).limit(21).to_a
    @next_page = rows.length > 20
    @tickets = rows.first(20)
  end

  def new
    head :forbidden and return if current_user.staff?
    @ticket = Ticket.new
  end

  def create
    head :forbidden and return if current_user.staff?
    @ticket = Ticket.new(params.expect(ticket: [:subject]))
    @ticket.customer = current_user
    body = params[:body]
    raise ActionController::BadRequest, "Message must be text" unless body.is_a?(String)
    Ticket.transaction do
      @ticket.save!
      @ticket.replies.create!(author: current_user, body: body)
    end
    redirect_to @ticket, status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @ticket.errors.add(:base, error.record.errors.full_messages.join(", ")) unless error.record == @ticket
    @body = body
    render :new, status: :unprocessable_entity
  end

  def show
    prepare_conversation
    @reply = Reply.new
  end

  def claim
    @ticket.claim_by!(current_user)
    redirect_to @ticket, status: :see_other, notice: "This ticket is assigned to you."
  rescue Ticket::Conflict => error
    render_conflict(error)
  end

  def close
    @ticket.change_status_by!(current_user, "closed")
    redirect_to @ticket, status: :see_other, notice: "Ticket closed."
  end

  def reopen
    @ticket.change_status_by!(current_user, "open")
    redirect_to @ticket, status: :see_other, notice: "Ticket reopened."
  end

  private

  def load_ticket
    @ticket = visible_tickets.find(params[:id])
  end

  def render_conflict(error)
    @reply = Reply.new
    flash.now[:alert] = error.message
    prepare_conversation
    render :show, status: :conflict
  end
end
