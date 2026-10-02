class CreateSupportDesk < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :role, null: false, default: "customer"
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_check_constraint :users, "role IN ('customer', 'staff')", name: "valid_user_role"
    create_table :tickets do |t|
      t.references :customer, null: false, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :subject, limit: 120, null: false
      t.string :status, null: false, default: "open"
      t.datetime :closed_at
      t.timestamps
    end
    add_check_constraint :tickets, "length(btrim(subject)) BETWEEN 1 AND 120", name: "ticket_subject_length"
    add_check_constraint :tickets, "(status = 'open' AND closed_at IS NULL) OR (status = 'closed' AND closed_at IS NOT NULL)", name: "ticket_status_timestamp"
    add_index :tickets, [:status, :created_at, :id], name: "ticket_queue"
    create_table :replies do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_check_constraint :replies, "length(btrim(body)) BETWEEN 1 AND 4000", name: "reply_body_length"
    add_index :replies, [:ticket_id, :created_at, :id], name: "reply_timeline"
  end
end
