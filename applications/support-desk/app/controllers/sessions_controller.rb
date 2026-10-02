class SessionsController < ApplicationController
  skip_before_action :require_user, only: [:new, :create]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { render plain: "Too many sign-in attempts. Try again later.", status: :too_many_requests }

  def new; end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password].to_s)
      reset_session
      session[:user_id] = user.id
      redirect_to tickets_path, status: :see_other
    else
      flash.now[:alert] = "Email or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path, status: :see_other
  end
end
