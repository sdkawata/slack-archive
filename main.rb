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
  @userhash = {}
  pgcon.exec('SELECT * FROM users').each{|user|
    @userhash[user['user_id']] = user
  }
  @channelname = params['channelname']
  res = pgcon.exec('SELECT * FROM channels where channel_name = $1', [@channelname])
  @channelid = res[0]['channel_id']
  @messages = pgcon.exec(
    'SELECT * FROM messages JOIN users ON users.user_id = messages.user_id WHERE channel_id = $1 ORDER BY created DESC',
    [@channelid]
  )
  @escape = lambda {|s|
    s.gsub(/<@([A-Za-z0-9]+)>/){|word|
      if @userhash.include?($1)
        '<@' + @userhash[$1]['user_name'] + '>'
      else
        word
      end
    }.gsub(/</, '&lt;').gsub(/>/, '&gt;').gsub(/\n/, '<br>')
  }
  erb :channel
end
