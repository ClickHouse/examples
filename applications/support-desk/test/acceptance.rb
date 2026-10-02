# Run through bin/rails runner against a dedicated migrated Cloud service.
require "minitest/autorun"
require "net/http"
require "securerandom"
require "socket"
require "pg"

class HttpSession
  attr_reader :token

  def initialize
    @cookie = nil
    @token = nil
  end

  def request(method, path, data = {}, csrf: true)
    uri = URI("http://127.0.0.1:3000#{path}")
    request = Net::HTTP.const_get(method.capitalize).new(uri)
    request["Cookie"] = @cookie if @cookie
    if method != "get"
      request.set_form_data(data.merge(csrf ? { "authenticity_token" => @token } : {}))
    end
    response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 20) { |http| http.request(request) }
    @cookie = response["Set-Cookie"].split(";").first if response["Set-Cookie"]
    @token = response.body[/name="csrf-token" content="([^"]+)"/, 1] || @token
    response
  end

  def login(user, password)
    request("get", "/session/new")
    response = request("post", "/session", { "email" => user.email, "password" => password })
    raise "Sign in failed: #{response.code}" unless response.code == "303"
    request("get", "/tickets")
    self
  end
end

module Fixtures
  PREFIX = "acceptance-#{SecureRandom.hex(6)}"
  PASSWORD = "FixturePass-#{SecureRandom.hex(12)}"
  USERS = ["customer", "customer", "staff", "staff"].each_with_index.map do |role, index|
    User.create!(name: "Fixture #{index}", email: "#{PREFIX}-#{index}@example.test", role: role, password: PASSWORD)
  end
  CLIENTS = USERS.map { |user| HttpSession.new.login(user, PASSWORD) }

  def self.cleanup
    ActiveRecord::Base.connection_pool.disconnect!
    PG.connect(host: ENV.fetch("PGHOST"), port: ENV.fetch("PGPORT", "5432"), dbname: ENV.fetch("PGDATABASE", "postgres"),
      user: "support_desk_migrator", password: ENV.fetch("TEST_MIGRATOR_PASSWORD"),
      sslmode: "verify-full", sslrootcert: ENV.fetch("PGSSLROOTCERT")) do |connection|
      USERS.each do |user|
        connection.exec_params("DELETE FROM support_desk.replies WHERE ticket_id IN (SELECT id FROM support_desk.tickets WHERE customer_id = $1)", [user.id])
        connection.exec_params("DELETE FROM support_desk.tickets WHERE customer_id = $1", [user.id])
      end
      USERS.each { |user| connection.exec_params("DELETE FROM support_desk.users WHERE id = $1", [user.id]) }
    end
  end
end
Minitest.after_run { Fixtures.cleanup }

class Acceptance < Minitest::Test
  def setup
    @ticket = Ticket.create!(customer: Fixtures::USERS[0], subject: "#{Fixtures::PREFIX} #{SecureRandom.hex(4)}")
    @clients = Fixtures::CLIENTS
  end

  def post(index, path, data = {})
    @clients[index].request("post", path, data)
  end

  def test_authentication_and_csrf
    assert_equal "302", HttpSession.new.request("get", "/tickets").code
    assert_equal "422", @clients[0].request("post", "/tickets", { "ticket[subject]" => "CSRF rejected", "body" => "Hello" }, csrf: false).code
    assert_equal "404", @clients[0].request("get", "/tickets/#{@ticket.id}/claim").code
  end

  def test_customer_identity_and_atomic_creation
    response = post(0, "/tickets", { "ticket[subject]" => "#{Fixtures::PREFIX} created", "ticket[customer_id]" => Fixtures::USERS[1].id, "body" => "First message" })
    assert_equal "303", response.code
    ticket = Ticket.order(:id).last
    assert_equal Fixtures::USERS[0].id, ticket.customer_id
    assert_equal Fixtures::USERS[0].id, ticket.replies.first.author_id
    before = Ticket.count
    assert_equal "422", post(0, "/tickets", { "ticket[subject]" => "Rollback", "body" => "   " }).code
    assert_equal before, Ticket.count
  end

  def test_validation_and_cross_customer_access
    assert_equal "422", post(0, "/tickets", { "ticket[subject]" => "   ", "body" => "Message" }).code
    assert_equal "404", @clients[1].request("get", "/tickets/#{@ticket.id}").code
    assert_equal "404", post(1, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Intrusion" }).code
    assert_equal "404", @clients[0].request("get", "/tickets/not-an-id").code
    refute_includes @clients[1].request("get", "/tickets").body, @ticket.subject
  end

  def test_competing_claims
    ready = Queue.new
    start = Queue.new
    threads = [2, 3].map do |index|
      Thread.new { ready << true; start.pop; post(index, "/tickets/#{@ticket.id}/claim").code }
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal ["303", "409"], threads.map(&:value).sort
    assert_includes Fixtures::USERS[2..3].map(&:id), @ticket.reload.assignee_id
  end

  def test_repeat_claim_and_staff_permissions
    assert_equal "403", post(0, "/tickets/#{@ticket.id}/claim").code
    assert_equal "403", post(2, "/tickets", { "ticket[subject]" => "Staff ticket", "body" => "Hello" }).code
    assert_equal "303", post(2, "/tickets/#{@ticket.id}/claim").code
    assert_equal "303", post(2, "/tickets/#{@ticket.id}/claim").code
    assert_equal "409", post(3, "/tickets/#{@ticket.id}/claim").code
    assert_equal "403", post(3, "/tickets/#{@ticket.id}/close").code
    assert_equal "403", post(3, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Wrong owner" }).code
    assert_equal Fixtures::USERS[2].id, @ticket.reload.assignee_id
  end

  def test_replies_and_closed_semantics
    assert_equal "403", post(2, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Unclaimed" }).code
    post(2, "/tickets/#{@ticket.id}/claim")
    assert_equal "303", post(0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Customer question", "reply[author_id]" => Fixtures::USERS[1].id }).code
    assert_equal Fixtures::USERS[0].id, @ticket.replies.last.author_id
    assert_equal "303", post(2, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Staff answer" }).code
    assert_equal "303", post(2, "/tickets/#{@ticket.id}/close").code
    closed_at = @ticket.reload.closed_at
    assert_equal "303", post(2, "/tickets/#{@ticket.id}/close").code
    assert_equal closed_at, @ticket.reload.closed_at
    assert_equal "409", post(0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Closed attempt" }).code
    assert_equal "409", post(2, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Staff closed attempt" }).code
    assert_equal 2, @ticket.replies.count
    assert_equal "303", post(2, "/tickets/#{@ticket.id}/reopen").code
    assert_nil @ticket.reload.closed_at
    assert_equal "303", post(0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "After reopen" }).code
  end

  def test_close_and_reply_share_the_ticket_lock
    post(2, "/tickets/#{@ticket.id}/claim")
    ready = Queue.new
    start = Queue.new
    threads = nil
    ActiveRecord::Base.transaction do
      @ticket.lock!
      operations = [[0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "Racing closure" }],
                    [2, "/tickets/#{@ticket.id}/close", {}]]
      threads = operations.map do |index, path, data|
        Thread.new { ready << true; start.pop; post(index, path, data).code }
      end
      2.times { ready.pop }
      2.times { start << true }
      sleep 0.5
      assert threads.all?(&:alive?), "both HTTP mutations must wait for the parent ticket lock"
    end
    reply_status, close_status = threads.map(&:value)
    assert_equal "303", close_status
    assert_includes ["303", "409"], reply_status
    assert @ticket.reload.closed?
    if reply_status == "303"
      assert_equal 1, @ticket.replies.count
      assert_operator @ticket.replies.first.created_at, :<=, @ticket.closed_at
    else
      assert_equal 0, @ticket.replies.count
    end
    assert_equal "409", post(0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "After closure" }).code
  end

  def test_reply_validation_and_deterministic_order
    assert_equal "422", post(0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "   " }).code
    assert_equal "422", post(0, "/tickets/#{@ticket.id}/replies", { "reply[body]" => "a" * 4001 }).code
    timestamp = Time.current
    replies = ["First same-time reply", "Second same-time reply"].map { |body| Reply.create!(ticket: @ticket, author: Fixtures::USERS[0], body: body, created_at: timestamp) }
    assert_equal replies.map(&:id), @ticket.replies.map(&:id)
    html = @clients[0].request("get", "/tickets/#{@ticket.id}").body
    assert_operator html.index(replies.first.body), :<, html.index(replies.last.body)
  end

  def test_bounded_ticket_and_reply_pages
    22.times { |n| Ticket.create!(customer: Fixtures::USERS[0], subject: "#{Fixtures::PREFIX} page #{n}") }
    html = @clients[0].request("get", "/tickets").body
    assert_equal 20, html.scan(/class="ticket-row"/).length
    assert_includes html, "Older tickets"
    assert_equal "400", @clients[0].request("get", "/tickets?page=0").code
    timestamp = Time.current
    51.times { |n| Reply.create!(ticket: @ticket, author: Fixtures::USERS[0], body: "Paged reply #{n}", created_at: timestamp) }
    latest = @clients[0].request("get", "/tickets/#{@ticket.id}").body
    assert_equal 50, latest.scan(/class="reply"/).length
    assert_includes latest, "Paged reply 50"
    refute_includes latest, ">Paged reply 0<"
    assert_includes latest, "Older replies"
    older = @clients[0].request("get", "/tickets/#{@ticket.id}?reply_page=2").body
    assert_equal 1, older.scan(/class="reply"/).length
    assert_includes older, "Paged reply 0"
    assert_equal "400", @clients[0].request("get", "/tickets/#{@ticket.id}?reply_page=bad").code
  end

  def test_runtime_permissions
    connection = ActiveRecord::Base.connection
    assert_raises(ActiveRecord::StatementInvalid) { connection.execute("CREATE TABLE support_desk.must_not_exist (id integer)") }
    assert_raises(ActiveRecord::StatementInvalid) { connection.execute("UPDATE support_desk.schema_migrations SET version = version") }
    assert_raises(ActiveRecord::StatementInvalid) { connection.execute("UPDATE support_desk.replies SET body = body") }
    assert_raises(ActiveRecord::StatementInvalid) { connection.execute("DELETE FROM support_desk.replies WHERE false") }
  end

  def test_database_constraints
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.connection.exec_query("UPDATE tickets SET status = 'closed', closed_at = NULL WHERE id = #{@ticket.id}")
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Reply.insert_all!([{ ticket_id: @ticket.id, author_id: Fixtures::USERS[0].id, body: " ", created_at: Time.current }])
    end
  end

  def test_verified_tls_and_negative_controls
    assert ActiveRecord::Base.connection.select_value("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")
    params = { host: ENV.fetch("PGHOST"), port: ENV.fetch("PGPORT", "5432"), dbname: ENV.fetch("PGDATABASE", "postgres"),
      user: ENV.fetch("PGUSER"), password: ENV.fetch("PGPASSWORD"), sslmode: "verify-full", connect_timeout: 10 }
    error = assert_raises(PG::ConnectionBad) { PG.connect(**params, sslrootcert: "/etc/ssl/certs/ca-certificates.crt") }
    assert_includes error.message.downcase, "certificate verify failed"
    params[:hostaddr] = IPSocket.getaddress(params[:host])
    params[:host] = "wrong-hostname.example.invalid"
    error = assert_raises(PG::ConnectionBad) { PG.connect(**params, sslrootcert: ENV.fetch("PGSSLROOTCERT")) }
    assert_includes error.message.downcase, "does not match host name"
  end
end
