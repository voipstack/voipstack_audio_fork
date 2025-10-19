require "log"
require "socket"
require "sip_utils"

# TODO: Write documentation for `VoipstackAudioFork`
module VoipstackAudioFork
  VERSION = "0.1.0"

  abstract class MediaDumper
    abstract def start(session_id : String, context : Hash(String, String))
    abstract def dump(session_id : String, data : Bytes)
    abstract def stop(session_id : String)
  end

  class Server
    Log = ::Log.for("voipstack_audio_fork_server")

    @sockets = [] of UDPSocket
    @dumpers = [] of MediaDumper
    @media_servers_by_call_id = Hash(String, UDPSocket).new
    @session_id = 0

    def initialize
      @pbx_socket = UDPSocket.new
    end

    def bind_pair(listen_host : String, listen_port : Int32, pbx_host : String, pbx_port : Int32) : Socket::IPAddress
      udp_server = UDPSocket.new
      udp_server.bind(listen_host, listen_port)
      @sockets << udp_server
      @pbx_socket.connect(pbx_host, pbx_port)

      udp_server.local_address
    end

    def attach_dumper(dumper : MediaDumper) : Nil
      @dumpers << dumper
    end

    def listen
      tagger = SIPUtils::Network::UA::DefaultTagger.new
      ua = SIPUtils::Network::UA.new(tagger: tagger)
      done = Channel(Nil).new

      @sockets.each do |socket|
        spawn do
          loop do
            break if socket.closed?
            message, client_addr = socket.receive(8096)
            Log.debug { "Received SIP Request from #{socket.local_address}: #{message}" }
            request = SIPUtils::Network::SIP(SIPUtils::Network::SIP::Request).parse(IO::Memory.new(message))
            case request.method
            when "ACK"
              Log.debug { "Received ACK from #{client_addr}, call established" }
            when "BYE"
              Log.debug { "Received BYE from #{client_addr}, call terminated" }
              stop_media_server(request.headers["Call-ID"])
              response = ua.answer_bye(request: request, via_address: socket.local_address.to_s)
              client_send(response)
            when "INVITE"
              Log.debug { "Received INVITE from #{client_addr}, call initiated" }
              next_session_id
              # TODO: start on ACK
              media_server_addr = start_media_server(request, socket.local_address.address.to_s)
              response = ua.answer_invite(request: request, media_address: media_server_addr.address.to_s, media_port: media_server_addr.port, session_id: @session_id.to_s, via_address: socket.local_address.to_s)

              client_send(response)
            end
          end
        ensure
          done.send nil
        end
      end

      @sockets.size.times { done.receive }
    end

    def has_media_server_for_call_id?(call_id : String)
      @media_servers_by_call_id.has_key?(call_id)
    end

    private def next_session_id
      @session_id += 1
      @session_id = 0 if @session_id >= Int32::MAX
    end

    private def stop_media_server(call_id : String)
      # TODO: kill zombies
      if @media_servers_by_call_id.has_key?(call_id)
        media_server = @media_servers_by_call_id[call_id]
        media_server.close
        @media_servers_by_call_id.delete(call_id)
      end
    end

    private def start_media_server(request, address : String)
      call_id = request.headers["Call-ID"]
      media_server = UDPSocket.new
      media_server.read_timeout = 1.second
      media_server.bind(address, 0)
      session_id = @session_id.to_s

      Log.debug { "MediaServer #{@session_id} Listening on #{media_server.local_address}" }
      @media_servers_by_call_id[call_id] = media_server

      @dumpers.each do |dumper|
        spawn name: "start_media_server(#{media_server.local_address} session id #{session_id})" do
          dumper.start(session_id, request.headers)
          buffer = Bytes.new(1500) # MTU

          loop do
            bytes_read, client_addr = media_server.receive(buffer)
            Log.debug { "MediaServer #{session_id} Received #{bytes_read} bytes from #{client_addr}" }
            dumper.dump(session_id, buffer[0, bytes_read])
          end
        ensure
          dumper.stop(session_id)
        end
      end

      media_server.local_address
    end

    private def client_send(response)
      Log.debug { "Sent response to #{@pbx_socket.local_address}: #{SIPUtils::Network.encode(response)}" }

      @pbx_socket.send SIPUtils::Network.encode(response)
    end

    def close
      @sockets.each do |socket|
        socket.close
      rescue
      end
    end
  end
end
