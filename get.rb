require 'net/http'

load 'common.rb'


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

  def initialize(teamname)
    @teamname = teamname
    @slackKey = getconfig()[teamname]['slack-api-key']
    @newmsg = 0
    puts "start archiving team " + teamname
    @logfile = File.open('slackapi_' + @teamname + '.log', 'w')
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
    @logfile.puts('api access:' + apiname + ' ' + param.to_s)
    @logfile.puts('result:' + response.to_s)
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
        @newmsg += 1
        message = messageAddField(message)
        @pgcon.exec(
          'INSERT INTO messages (channel_id, user_id, text, created,ts) VALUES ($1,$2,$3,$4,$5)',
          [channel['id'],message['user'],message['text'],message['created'],message['ts']])
      end
      if history['has_more']
        meslatest = messages.sort_by{|message| message['created']}[0]['ts']
        puts 'current latest ts=' + meslatest.to_s
        if oldest != '0'
          oldest = meslatest
        else
          latest = meslatest
        end
      else
        break
      end
    end
  end

  def saveUserLists()
    @userhash = {}
    usersList = slackapi('users.list', {})['members']
    usersList.each do |user|
      res = @pgcon.exec('SELECT * FROM users WHERE user_id = $1', [user['id']])
      userstr = 'user id=' + user['id'] + ' name='+ user['name']
      @userhash[user['id']] = user
      if res.num_tuples > 0
        puts userstr + ' found in DB. updating'
        @pgcon.exec(
          'UPDATE users SET user_name = $1, user_image = $2 where user_id = $3',
          [user['name'], user['profile']['image_192'] , user['id']]
        )
      else
        puts userstr + ' not found in DB. inserting'
        @pgcon.exec(
          'INSERT INTO users (user_id, user_name, user_image) VALUES ($1, $2, $3)',
          [user['id'], user['name'], user['profile']['image_192']]
        )
      end
    end
  end

  def archive()
    @pgcon = pgconnect(@teamname)
    saveUserLists()
    @@channel_types.each_pair{|type, name|
      puts 'starting to archive channels of type ' + name
      apiname = @@channel_apinames[type]
      channelsList = slackapi(apiname + '.list', {})[@@channel_channelskey[type]]
      channelsList.each do |channel|
        res = @pgcon.exec('SELECT * FROM channels where channel_id = $1', [channel['id']])
        if name == 'im'
          channel['name'] = 'im_with_' + @userhash[channel['user']]['name']
        end
        channelstr = 'channel id=' + channel['id'] + ' name=' + channel['name']
        if res.num_tuples > 0
          puts channelstr + ' found in DB. updating'
          @pgcon.exec(
            'UPDATE channels SET channel_name = $1 where channel_id = $2',
            [channel['name'], channel['id']]
          )
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
    puts 'new msg:' + @newmsg.to_s
    close()
  end
  def close()
    @logfile.close()
  end
end

getconfig().each_key{|teamname|
  SlackArchive.new(teamname).archive()
}
