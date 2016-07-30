require 'json'
require 'net/http'
require 'pg'


class SlackArchive
  @@channel_types = {
    0 => 'public',
    1 => 'private',
    2 => 'im',
    3 => 'multiim'
  }

  @@channel_apinames = {
    0 => 'channels',
    1 => 'groups',
    2 => 'im',
    3 => 'mpim'
  }

  @@channel_channelskey = {
    0 => 'channels',
    1 => 'groups',
    2 => 'ims',
    3 => 'groups'
  }

  def initialize()
    keys = open('key.json') do |io|
      JSON.load(io)
    end
    @slackKey = keys['slack-api-key']
  end

  def slackapi(apiname, param)
    uri = URI.parse('https://slack.com/api/' + apiname)
    request = Net::HTTP::Post.new(uri.path)
    param['token'] = @slackKey
    request.set_form_data(param)
    http = Net::HTTP.new(uri.host,uri.port)
    http.use_ssl = true
    response = http.start do |h|
      h.request(request).body
    end
    response = JSON.parse(response)
    if response['ok'] == true
      response
    else
      puts 'error'
      puts response
      response
    end
  end

  def archiveChannel(channel)
    channelstr = 'channel id=' + channel['id'] + ' name=' + channel['name']
    latest = 'now'
    oldest = '0'
    puts 'trying to retrieve message of ' + channelstr
    count = @pgcon.exec(
      'SELECT COUNT(*) as count FROM messages where channel_id = $1',
      [channel['id']]
    )[0]['count']
    if count.to_i == 0
      puts 'no messages found in DB. retriving from latest messages'
    else
      maxcreated = @pgcon.exec(
        'SELECT MAX(created) AS max FROM messages where channel_id = $1',
        [channel['id']]
      )
      maxts = @pgcon.exec(
        'SELECT ts FROM messages where channel_id = $1 AND created = $2',
        [channel['id'], maxcreated[0]['max']]
      )
      if maxts.num_tuples > 1
        puts '**warning** multple max created'
      end
      oldest = maxts[0]['ts']
      puts 'some messages found in DB. retriving from ts=' + oldest
    end
    while true
      param = {'channel' => channel['id'], 'count' => 1000, 'oldest' => oldest}
      if latest != 'now'
        param['latest'] = latest
      end
      history = slackapi(channel['apiname'] + '.history', param)
      messages = history['messages']
      puts 'retrived history latest=' + history['latest'].to_s +
           ' has_more=' + history['has_more'].to_s + ' num=' + messages.size.to_s
      messages.each do |message|
        if @pgcon.exec('SELECT * FROM messages WHERE channel_id=$1 AND ts=$2',[channel['id'], message['ts']]).num_tuples > 0
          puts 'same message found in DB'
          next
        end
        message['created'] = Time.at(message['ts'].split('.')[0].to_i)
        @pgcon.exec(
          'INSERT INTO messages (channel_id, user_id, text, created,ts) VALUES ($1,$2,$3,$4,$5)',
          [channel['id'],message['user'],message['text'],message['created'],message['ts']])
      end
      if history['has_more']
        latest = messages.sort_by{|message| message['created']}[0]['ts']
        puts 'next latest ts=' + latest.to_s
      else
        break
      end
    end
  end

  def archive()

    @pgcon = PG::connect(:host => 'localhost', :user => 'kawata', :dbname => 'slack', :password => 'hoge')
    @pgcon.internal_encoding= 'UTF-8'
    @@channel_types.each_pair{|type, name|
      puts 'starting to archive channels of type ' + name
      apiname = @@channel_apinames[type]
      channelsList = slackapi(apiname + '.list', {})[@@channel_channelskey[type]]
      channelsList.each do |channel|
        res =@pgcon.exec('SELECT * FROM channels where channel_id = $1', [channel['id']])
        if name == 'im'
          channel['name'] = 'im with ' + channel['user']
        end
        channelstr = 'channel id=' + channel['id'] + ' name=' + channel['name']
        if res.num_tuples > 0
          puts channelstr + ' found in DB.'
        else
          puts channelstr + ' NOT found in DB. inserting'
          @pgcon.exec(
            'INSERT INTO channels (channel_id, channel_name,channel_type) VALUES ($1,$2, $3)',
            [channel['id'], channel['name'], type]
          )
        end
        res.clear
      end

      channelsList.each do |channel|
        channel['apiname'] = apiname
        archiveChannel(channel)
      end
    }
  end
end

SlackArchive.new().archive()
