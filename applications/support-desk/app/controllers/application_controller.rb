class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :require_user
  helper_method :current_user
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  rescue_from Ticket::Forbidden, with: -> { head :forbidden }
  rescue_from ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, with: :database_unavailable

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def require_user
    redirect_to new_session_path unless current_user
  end

  def visible_tickets
    current_user.staff? ? Ticket.all : Ticket.where(customer: current_user)
  end

  def page_number(key)
    value = params.fetch(key, "1").to_s
    raise ActionController::BadRequest, "Invalid page" unless value.match?(/\A[1-9]\d{0,2}\z/)
    value.to_i
  end

  def prepare_conversation
    @reply_page = page_number(:reply_page)
    rows = @ticket.replies.reorder(created_at: :desc, id: :desc)
      .includes(:author).offset((@reply_page - 1) * 50).limit(51).to_a
    @older_replies = rows.length > 50
    @replies = rows.first(50).reverse
  end

  def database_unavailable
    render plain: "The database is busy. Refresh and try again.", status: :service_unavailable
  end
end
