require 'net/http'
require 'uri'
require 'json'

namespace :db do
  task :create do
    # config = ARTest.config['connections']['postgresql']
    %x( createdb -E UTF8 -T template0 que-test )
    # %x( createdb -E UTF8 -T template0 #{config['arunit2']['database']} )

    # # prepare hstore
    # if %x( createdb --version ).strip.gsub(/(.*)(\d\.\d\.\d)$/, "\\2") < "9.1.0"
    #   puts "Please prepare hstore data type. See http://www.postgresql.org/docs/9.0/static/hstore.html"
    # end
  end

  desc 'Drop the PostgreSQL test databases'
  task :drop do
     %x( dropdb que-test )
  end

  # desc 'Rebuild the PostgreSQL test databases'
  # task :rebuild => [:drop, :build]
end

# namespace :benches do
#   task :press do
#     uri = URI.parse("http://requestb.in/18tdza31")
#     task :default
#     response = Net::HTTP.post_form(uri, {metrics: "hai"})
#     STDOUT.puts response.inspect
#   end
# end

# task :default do
namespace :benches do
  task :press do
    task_start = Time.now
    uri = URI.parse("http://requestb.in/18tdza31")
    response = Net::HTTP.post_form(uri, {message: "started"})

    require 'uri'
    require 'bundler'
    Bundler.require

    QUIET              = !!ENV['QUIET']
    ITERATIONS         = (ENV['ITERATIONS'] || 5).to_i
    TEST_PERIOD        = (ENV['TEST_PERIOD'] || 0.2).to_f
    WARMUP_PERIOD      = (ENV['WARMUP_PERIOD'] || 0.2).to_f
    JOB_COUNT          = (ENV['JOB_COUNT'] || 1000).to_i
    SYNCHRONOUS_COMMIT = ENV['SYNCHRONOUS_COMMIT'] || 'on'

    QUEUES = {}

    DATABASE_URL = ENV['DATABASE_URL'] || 'postgres://postgres:@localhost/que-test'
    DATABASE_URI = URI.parse(DATABASE_URL)

    NEW_PG = -> do
      pg = PG::Connection.open :host     => DATABASE_URI.host,
        :user     => DATABASE_URI.user,
        :password => DATABASE_URI.password,
        :port     => DATABASE_URI.port || 5432,
        :dbname   => DATABASE_URI.path[1..-1]

      pg.async_exec "SET SESSION synchronous_commit = #{SYNCHRONOUS_COMMIT}"
      pg.async_exec "SET client_min_messages TO 'warning'" # Avoid annoying notice messages.
      pg
    end

    # We have to watch our database connections, because they'll become unusable
    # whenever we fork. This pg connection is only used during setup in the main
    # process, and the redis connection is reestablished after forking.
    $pg    = NEW_PG.call
    $redis = Redis.new :url    => ENV['REDIS_URL'],
      :driver => :hiredis

    %w(delayed_job queue_classic que).each { |queue| require "./queues/#{queue}" }

    $pg.async_exec "ANALYZE"



    # For large numbers of workers, we remove Ruby's GIL as the bottleneck by
    # forking off child processes to act as workers, while the parent process
    # manages them and tracks their performance.

    parent_pid = Process.pid
    define_method(:parent?) { parent_pid == Process.pid }

    puts "Benchmarking #{QUEUES.keys.join(', ')}"
    puts "  QUIET = #{QUIET}"
    puts "  ITERATIONS = #{ITERATIONS}"
    puts "  DATABASE_URL = #{DATABASE_URL}"
    puts "  JOB_COUNT = #{JOB_COUNT}"
    puts "  TEST_PERIOD = #{TEST_PERIOD}"
    puts "  WARMUP_PERIOD = #{WARMUP_PERIOD}"
    puts "  SYNCHRONOUS_COMMIT = #{SYNCHRONOUS_COMMIT}"
    puts

    peaks = {}

    ITERATIONS.times do |i|
      puts "Iteration ##{i + 1}:" unless QUIET

      QUEUES.each do |queue, procs|
        peaks[queue] ||= []
        worker_count   = 1
        rates          = []

        print "#{queue}: " unless QUIET

        loop do
          $redis.flushdb
          worker_count.times { Process.fork if parent? }
          $redis.client.reconnect

          if parent?
            # Give workers a chance to warm up before we start tracking their progress.
            sleep WARMUP_PERIOD

            # Reset the counter and count the jobs done over TEST_PERIOD seconds.
            # Ruby may let this thread sleep longer than TEST_PERIOD, so don't
            # trust that value, and actually measure the elapsed time.
            $redis.set 'job-count', 0
            start = Time.now
            sleep TEST_PERIOD
            count = $redis.get('job-count').to_i
            elapsed_time = Time.now - start
            rates << (count / elapsed_time)

            # Signal child processes to exit.
            $redis.set 'job-count', -1_000_000

            Process.waitall
          else
            # We're a child/worker process. First, establish connections.
            procs[:setup].call

            loop do
              # Work job.
              procs[:work].call

              # Mark job as completed. If this is negative, it means we're shutting down.
              break if $redis.incr('job-count') < 0
            end

            exit
          end

          print "#{rates.count} => #{rates.last.round(1)}" unless QUIET

          # If the peak productivity was not in the past three data points,
          # assume the slope is trending down and we're done.
          peak   = rates.max
          recent = rates.last(5)
          if recent.length == 5 && !recent.include?(peak)
            puts unless QUIET
            puts "#{queue}: Peaked at #{rates.index(peak) + 1} workers with #{peak.round(1)} jobs/second\n" unless QUIET

            peaks[queue] << peak
            break
          else
            # Try again with one more worker.
            print ", "  unless QUIET
            worker_count += 1
          end
        end
      end

      puts
    end

    things = []
    peaks.each do |queue, array|
      sum    = array.inject(:+)
      avg    = sum / array.length
      stddev = Math.sqrt(array.inject(0){|total, t| total + (t - avg)**2 } / (array.length - 1))

      things << {queue: queue, max: array.max.round(1), sum: sum, avg: avg.round(1), stddev: stddev.round(1)}

      puts "#{queue} jobs per second: avg = #{avg.round(1)}, max = #{array.max.round(1)}, min = #{array.min.round(1)}, stddev = #{stddev.round(1)}"
    end
    # response = Net::HTTP.post_form(uri, {message: "stopped"})
    req = Net::HTTP::Post.new(uri, initheader = {'Content-Type' =>'application/json'})
    req.body = {total_time: "#{(Time.now - task_start).round(1)} seconds", results: things}.to_json
    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end
    # puts
    # puts "Total runtime: #{(Time.now - task_start).round(1)} seconds"
    # response = Net::HTTP.post_form(uri, )
  end
end
