password = ENV.fetch("DEMO_PASSWORD")
raise "DEMO_PASSWORD must contain at least 12 characters" if password.length < 12
User.transaction do
  [["alex@example.test", "Alex", "customer"], ["sam@example.test", "Sam", "customer"],
   ["morgan@example.test", "Morgan", "staff"], ["jordan@example.test", "Jordan", "staff"]].each do |email, name, role|
    User.find_or_create_by!(email: email) do |user|
      user.name = name
      user.role = role
      user.password = password
    end
  end
  customer = User.find_by!(email: "alex@example.test")
  unless Ticket.exists?(subject: "Help connecting a new workspace")
    Ticket.transaction do
      ticket = Ticket.create!(customer: customer, subject: "Help connecting a new workspace")
      ticket.replies.create!(author: customer, body: "I have a new workspace and would like help with the first connection.")
    end
  end
end
puts "Demo customers, staff and one ticket are ready."
