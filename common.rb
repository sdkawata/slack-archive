require 'pg'
require 'json'

$config = open('key.json') do |io|
  JSON.load(io)
end

def getconfig()
  $config
end

def pgconnect(teamname)
  config = getconfig()
  res = PG::connect(
    :host => config[teamname]['db']['host'],
    :user => config[teamname]['db']['user'],
    :dbname =>  config[teamname]['db']['dbname'],
    :password =>  config[teamname]['db']['password']
  )
  res.internal_encoding= 'UTF-8'
  res
end

def messageAddField(message)
  message['created'] = Time.at(message['ts'].split('.')[0].to_i)
  if message.include?('attachments')
    message['attachments'].each do |attachment|
      if !attachment.include?('fallback')
        next
      end
      message['text'] = message['text'] + (message['text'] == '' ? '' : "\n") + "--\n" + attachment['fallback']
    end
  end
  message
end
