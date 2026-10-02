class Ticket < ApplicationRecord
  class Conflict < StandardError; end
  class Forbidden < StandardError; end

  belongs_to :customer, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true
  has_many :replies, -> { order(:created_at, :id) }, dependent: :restrict_with_exception
  normalizes :subject, with: ->(subject) { subject.strip }
  validates :subject, presence: true, length: { maximum: 120 }
  enum :status, { open: "open", closed: "closed" }, validate: true

  def claim_by!(user)
    raise Forbidden unless user.staff?
    with_lock do
      raise Conflict, "This ticket is closed." if closed?
      raise Conflict, "Another staff member owns this ticket." if assignee_id && assignee_id != user.id
      update!(assignee: user) unless assignee_id
    end
  end

  def reply_by!(user, body)
    with_lock do
      authorized = user.staff? ? assignee_id == user.id : customer_id == user.id
      raise Forbidden unless authorized
      raise Conflict, "Closed tickets cannot receive replies. Reopen the ticket first." if closed?
      replies.create!(author: user, body: body)
    end
  end

  def change_status_by!(user, desired)
    with_lock do
      raise Forbidden unless user.staff? && assignee_id == user.id
      raise ArgumentError unless %w[open closed].include?(desired)
      update!(status: desired, closed_at: desired == "closed" ? (closed_at || Time.current) : nil)
    end
  end
end
