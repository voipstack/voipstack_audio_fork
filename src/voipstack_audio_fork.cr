require "log"
require "socket"

# TODO: Write documentation for `VoipstackAudioFork`
module VoipstackAudioFork
  VERSION = "0.1.0"

  class Server
    Log = ::Log.for("voipstack_audio_fork_server")

    @sockets = [] of UDPSocket

    def bind_udp(host : String, port : Int32) : Socket::IPAddress
      udp_server = UDPSocket.new
      udp_server.bind(host, port)
      @sockets << udp_server
      udp_server.local_address
    end

    def listen
      tagger = SIPUtils::Network::UA::DefaultTagger.new
      ua = SIPUtils::Network::UA.new(tagger: tagger)
      done = Channel(Nil).new

      @sockets.each do |socket|
        spawn do
          loop do
            break if socket.closed?
            message, _ = socket.receive(8096)
            request = SIPUtils::Network::SIP(SIPUtils::Network::SIP::Request).parse(IO::Memory.new(message))
            client_addr = ua.parse_via_address(request)

            case request.method
            when "ACK"
              Log.debug { "Received ACK, cal established" }
            when "BYE"
              Log.debug { "Received BYE, call terminated" }
              response = ua.answer_bye(request: request, via_address: socket.local_address.to_s)
              client_send(client_addr, response)
            when "INVITE"
              Log.debug { "Received INVITE, call initiated" }
              response = ua.answer_invite(request: request, media_address: "0.0.0.0", media_port: 0, session_id: "0", via_address: socket.local_address.to_s)
              client_send(client_addr, response)
            end
          end
        ensure
          done.send nil
        end
      end

      @sockets.size.times { done.receive }
    end

    private def client_send(client_addr, response)
      client = UDPSocket.new
      client.connect client_addr
      client.send SIPUtils::Network.encode(response)
      client.close
    end

    def close
      @sockets.each do |socket|
        socket.close
      rescue
      end
    end
  end
end
