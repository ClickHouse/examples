class RepliesController < ApplicationController
  def create
    @ticket = visible_tickets.find(params[:ticket_id])
    @ticket.reply_by!(current_user, params.expect(reply: [:body])[:body])
    redirect_to @ticket, status: :see_other, notice: "Reply added."
  rescue ActiveRecord::RecordInvalid => error
    @reply = error.record
    prepare_conversation
    render "tickets/show", status: :unprocessable_entity
  rescue Ticket::Conflict => error
    @reply = Reply.new
    flash.now[:alert] = error.message
    prepare_conversation
    render "tickets/show", status: :conflict
  end
end
