threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", "5"))
threads threads_count, threads_count
bind "tcp://127.0.0.1:#{ENV.fetch('PORT', '3000')}"
plugin :tmp_restart
