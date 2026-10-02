class Reply < ApplicationRecord
  belongs_to :ticket
  belongs_to :author, class_name: "User"
  normalizes :body, with: ->(body) { body.strip }
  validates :body, presence: true, length: { maximum: 4000 }
end
