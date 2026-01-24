require "uri"
require "log"
require "option_parser"
require "sip_utils"
require "http/web_socket"
require "./voipstack_audio_fork.cr"

Log.setup_from_env(default_level: Log::Severity::Debug)

listen_host = "127.0.0.1"
listen_port = 5060
pbx_host = "127.0.0.1"
pbx_port = 5080

media_dump_url = "raw:///tmp/audio{Call-ID}.ulaw"

OptionParser.parse do |parser|
  parser.banner = "Usage: voipstack_audio_fork [options]"

  parser.on("-s URL", "--pbx=URL", "PBX URL") do |url|
    pbx_host, pbx_port = URI.parse(url).host.not_nil!, URI.parse(url).port.not_nil!
  end

  parser.on("-l HOST", "--listen=HOST", "Listen host") do |host|
    listen_host = host
  end

  parser.on("-p PORT", "--port=PORT", "Listen port") do |port|
    listen_port = port.to_i
  end

  parser.on("-o", "--output FILE", "Output file (#{media_dump_url})") do |url|
    media_dump_url = url
  end

  parser.on("-h", "--help", "Display this help message") do
    puts parser
    exit
  end
end

class FileMediaDumper < VoipstackAudioFork::MediaDumper
  Log = ::Log.for("voipstack_audio_fork::cli::FileMediaDumper")

  def initialize(output_path : String)
    @jitter_buffers = Hash(String, VoipstackAudioFork::JitterBuffer).new
    @output_path = output_path
  end

  def start(session_id, context : Hash(String, String))
    Log.info { "Starting media dump for session #{session_id} : #{context.inspect}" }

    file = File.open(render_output_path(context), "wb")
    writer = VoipstackAudioFork::FileJitterWriter.new(file)
    @jitter_buffers[session_id] = VoipstackAudioFork::JitterBuffer.new(writer)
  end

  def dump(session_id, data : Bytes)
    Log.info { "Dumping data for session #{session_id}" }
    jitter_buffer = @jitter_buffers[session_id]?
    jitter_buffer.try(&.write(data))
  end

  def stop(session_id)
    Log.info { "Stopping media dump for session #{session_id}" }
    if jitter_buffer = @jitter_buffers[session_id]?
      jitter_buffer.writer.close
      @jitter_buffers.delete(session_id)
    end
  end

  private def render_output_path(context : Hash(String, String))
    output_path = context.reduce(@output_path) do |path, (key, value)|
      path.gsub("{#{key}}", value)
    end
    output_path
  end
end

class WebsocketMediaDumper < VoipstackAudioFork::MediaDumper
  Log = ::Log.for("voipstack_audio_fork::cli::WebsocketMediaDumper")

  def initialize(websocket_url : String)
    @websocket_url = websocket_url
    @jitter_buffers = Hash(String, VoipstackAudioFork::JitterBuffer).new
  end

  def start(session_id, context : Hash(String, String))
    Log.info { "Starting websocket media dump for session #{session_id} : #{context.inspect}" }

    url = render_websocket_url(context)

    Log.info { "Websocket URL: #{url}" }
    ws = HTTP::WebSocket.new(URI.parse(url))
    writer = VoipstackAudioFork::WebsocketJitterWriter.new(ws)
    jitter_buffer = VoipstackAudioFork::JitterBuffer.new(writer)
    @jitter_buffers[session_id] = jitter_buffer

    spawn do
      ws.run
    rescue ex
      Log.error(exception: ex) { "Websocket error for session #{session_id}" }
    end
  end

  def dump(session_id, data : Bytes)
    Log.debug { "Dumping data for session #{session_id} to websocket" }
    jitter_buffer = @jitter_buffers[session_id]?
    jitter_buffer.try(&.write(data))
  end

  def stop(session_id)
    Log.info { "Stopping websocket media dump for session #{session_id}" }
    @jitter_buffers.delete(session_id)
  end

  private def render_websocket_url(context : Hash(String, String))
    # use custom url from sip header
    if context.has_key?("X-VOIPSTACK-STREAM-IN-URL")
      return context["X-VOIPSTACK-STREAM-IN-URL"]
    else
      url = context.reduce(@websocket_url) do |path, (key, value)|
        path.gsub("{#{key}}", value)
      end
      return url
    end
  end
end

audio_fork = VoipstackAudioFork::Server.new
media_dump_uri = URI.parse(media_dump_url)
Log.info { "Media dump URL: #{media_dump_uri}" }
case media_dump_uri.scheme
when "raw"
  media_dumper = FileMediaDumper.new(media_dump_uri.path)
when "ws"
  media_dumper = WebsocketMediaDumper.new(media_dump_uri.to_s)
else
  raise "Unsupported media dump scheme: #{media_dump_uri.scheme}"
end

address = audio_fork.bind_pair(listen_host, listen_port, pbx_host, pbx_port)
audio_fork.attach_dumper(media_dumper)
Log.info { "Listening on #{address}" }
audio_fork.listen
