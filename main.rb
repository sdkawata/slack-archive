require 'sinatra'
require 'pg'

def pgconnect()
  res = PG::connect(:host => 'localhost', :user => 'kawata', :dbname => 'slack', :password => 'hoge')
  res.internal_encoding= 'UTF-8'
  res
end

def hoge()
  'hoge'
end
get '/' do
  'Hello, sinatra'
end

get '/channels' do
  pgcon = pgconnect()
  @channels = pgcon.exec('SELECT * FROM channels')
  erb :channels
end

get '/channel/:channelname' do
  pgcon = pgconnect()
  @channelname = params['channelname']
  res = pgcon.exec('SELECT * FROM channels where channel_name = $1', [@channelname])
  @channelid = res[0]['channel_id']
  @messages = pgcon.exec('SELECT * FROM messages where channel_id = $1 ORDER BY created DESC', [@channelid])
  @escape = lambda {|s|
    s.gsub(/</, '&lt;').gsub(/>/, '&gt;').gsub(/\n/, '<br>')
  }
  erb :channel
end
