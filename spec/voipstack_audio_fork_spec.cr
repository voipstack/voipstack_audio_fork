require "sip_utils"
require "./spec_helper"

def run_audio_fork(audio_fork, &)
  spawn do
    audio_fork.listen
  end

  begin
    yield
  ensure
    audio_fork.close
  end
end

class UAC
  def initialize
    @socket = UDPSocket.new
    @inbound = UDPSocket.new
  end

  def pair(address : Socket::IPAddress)
    @socket.connect address
    @inbound.bind("127.0.0.1", 0)
  end

  def host
    @inbound.local_address.address
  end

  def port
    @inbound.local_address.port
  end

  def send(request)
    @socket.send(SIPUtils::Network.encode(request))
  end

  def recv
    message, _ = @inbound.receive(8096)
    SIPUtils::Network::SIP(SIPUtils::Network::SIP::Response).parse(IO::Memory.new(message))
  end
end

def uac_send(client, request)
  client.send(SIPUtils::Network.encode(request))
end

describe VoipstackAudioFork do
  it "binds to unused port" do
    audio_fork = VoipstackAudioFork::Server.new
    address = audio_fork.bind_udp("127.0.0.1", 0)
    address.port.should_not eq(0)
    audio_fork.close
  end

  it "flow INVITE/Response/ACK only PCMU" do
    audio_fork = VoipstackAudioFork::Server.new
    address = audio_fork.bind_udp("127.0.0.1", 0)
    uac = UAC.new
    uac.pair(address)

    run_audio_fork(audio_fork) do
      request = SIPUtils::Network::SIP::Request.new("INVITE", "sip:bob@example.com", "SIP/2.0")
      request.headers["Via"] = "SIP/2.0/UDP #{uac.host}:#{uac.port};branch=z9hG4bK776asdhj"
      request.headers["From"] = "Alice <sip:alice@example.com>;tag=12345"
      request.headers["To"] = "Bob <sip:bob@example.com>;tag=67890"
      request.headers["Call-ID"] = "1234567890@example.com"
      request.headers["CSeq"] = "1 INVITE"
      request.headers["Content-Length"] = "0"
      uac.send(request)
      response = uac.recv

      response.headers["Content-Type"].should eq("application/sdp")
      sdp = SIPUtils::Network::SIP(SIPUtils::Network::SIP::SDP).parse(IO::Memory.new(response.body || ""))
      sdp.attributes[0].should eq("rtpmap:0 PCMU/8000")

      bye_request = SIPUtils::Network::SIP::Request.new("BYE", "sip:bob@example.com", "SIP/2.0")
      bye_request.headers["Via"] = "SIP/2.0/UDP #{uac.host}:#{uac.port};branch=z9hG4bK776asdhj"
      bye_request.headers["From"] = "Alice <sip:alice@example.com>;tag=12345"
      bye_request.headers["To"] = "Bob <sip:bob@example.com>;tag=67890"
      bye_request.headers["Call-ID"] = "1234567890@example.com"
      bye_request.headers["CSeq"] = "2 BYE"
      bye_request.headers["Content-Length"] = "0"
      uac.send(bye_request)
      response = uac.recv
      response.status_code.should eq(200)
    end
  end
end
