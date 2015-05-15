require 'uri'
require 'net/http'
require 'json'

class Bench
  # BENCHES_URL = 'http://requestb.in/18tdza31'
  BENCHES_URL = 'http://boiling-scrubland-5198.herokuapp.com/api/builds'

  def self.press(results)
    uri = URI.parse(BENCHES_URL)
    request = Net::HTTP::Post.new(uri, initheader = {'Content-Type' =>'application/json'})


    build = {
      project: ENV['CIRCLE_PROJECT_USERNAME'] + '/' + ENV['CIRCLE_PROJECT_REPONAME'],
      branch: ENV['CIRCLE_BRANCH'],
      commit_sha: ENV['CIRCLE_SHA1'],
      commit_timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S')
    }

    request.body = { build: build, metrics: results}.to_json

    Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
  end
end

