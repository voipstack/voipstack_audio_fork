require "sip_utils"
require "./spec_helper"

class DummyMediaDumper < VoipstackAudioFork::MediaDumper
  getter :bytes

  def initialize
    @bytes = 0
  end

  def start(session_id, context : Hash(String, String))
    Log.debug { "Dumper #{session_id} : #{context.inspect} started" }
  end

  def dump(session_id, data)
    Log.debug { "Dumper #{session_id} dumped #{data.size} bytes" }
    @bytes += data.size
  end

  def stop(session_id)
    Log.debug { "Dumper #{session_id} stopped" }
  end
end

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

  def pair(address : Socket::IPAddress, inbound_port : Int32)
    @socket.connect address
    @inbound.bind("127.0.0.1", inbound_port)
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

  def stream_audio(sdp, filepath)
    media_host = sdp.connection.split[2]
    media_port = sdp.media.split[1].to_i

    media_conn = UDPSocket.new
    media_conn.connect media_host, media_port
    Log.debug { "Streaming audio to #{media_host}:#{media_port}" }

    File.open(filepath, "r") do |file|
      buffer = Bytes.new(1500)
      while file.read(buffer) > 0
        media_conn.send(buffer)
      end
    end

    media_conn.close
  end
end

def uac_send(client, request)
  client.send(SIPUtils::Network.encode(request))
end

describe VoipstackAudioFork do
  it "binds to unused port" do
    audio_fork = VoipstackAudioFork::Server.new
    address = audio_fork.bind_pair("127.0.0.1", 0, "127.0.0.1", 0)
    address.port.should_not eq(0)
    audio_fork.close
  end

  it "receive BYE on empty state" do
    dumper = DummyMediaDumper.new
    audio_fork = VoipstackAudioFork::Server.new
    audio_fork.attach_dumper(dumper)
    address = audio_fork.bind_pair("127.0.0.1", 0, "127.0.0.1", 7676)
    uac = UAC.new
    uac.pair(address, 7676)

    run_audio_fork(audio_fork) do
      bye_request = SIPUtils::Network::SIP::Request.new("BYE", "sip:bob@example.com", "SIP/2.0")
      bye_request.headers["Via"] = "SIP/2.0/UDP #{uac.host}:#{uac.port};branch=z9hG4bK776asdhj"
      bye_request.headers["From"] = "Alice <sip:alice@example.com>;tag=12345"
      bye_request.headers["To"] = "Bob <sip:bob@example.com>;tag=67890"
      bye_request.headers["Call-ID"] = "1234567890@example.com"
      bye_request.headers["CSeq"] = "2 BYE"
      bye_request.headers["Content-Length"] = "0"
      uac.send(bye_request)
      # check BYE response
      response = uac.recv
      response.status_code.should eq(200)
    end
  end

  it "flow INVITE/Response/ACK only PCMU" do
    dumper = DummyMediaDumper.new
    audio_fork = VoipstackAudioFork::Server.new
    audio_fork.attach_dumper(dumper)
    address = audio_fork.bind_pair("127.0.0.1", 0, "127.0.0.1", 7676)
    uac = UAC.new
    uac.pair(address, 7676)

    run_audio_fork(audio_fork) do
      # send INVITE
      request = SIPUtils::Network::SIP::Request.new("INVITE", "sip:bob@example.com", "SIP/2.0")
      request.headers["Via"] = "SIP/2.0/UDP #{uac.host}:#{uac.port};branch=z9hG4bK776asdhj"
      request.headers["From"] = "Alice <sip:alice@example.com>;tag=12345"
      request.headers["To"] = "Bob <sip:bob@example.com>;tag=67890"
      request.headers["Call-ID"] = "1234567890@example.com"
      request.headers["CSeq"] = "1 INVITE"
      request.headers["Content-Length"] = "0"
      uac.send(request)
      response = uac.recv

      # check INVITE response
      response.headers["Content-Type"].should eq("application/sdp")
      sdp = SIPUtils::Network::SIP(SIPUtils::Network::SIP::SDP).parse(IO::Memory.new(response.body || ""))
      sdp.attributes[0].should eq("rtpmap:0 PCMU/8000")

      # send ACK
      ack_request = SIPUtils::Network::SIP::Request.new("ACK", "sip:bob@example.com", "SIP/2.0")
      ack_request.headers["Via"] = "SIP/2.0/UDP #{uac.host}:#{uac.port};branch=z9hG4bK776asdhj"
      ack_request.headers["From"] = "Alice <sip:alice@example.com>;tag=12345"
      ack_request.headers["To"] = "Bob <sip:bob@example.com>;tag=67890"
      ack_request.headers["Call-ID"] = "1234567890@example.com"
      ack_request.headers["CSeq"] = "1 ACK"
      ack_request.headers["Content-Length"] = "0"
      uac.send(ack_request)

      sleep 0.1.seconds
      audio_fork.has_media_server_for_call_id?(request.headers["Call-ID"]).should be_true

      # stream audio
      uac.stream_audio(sdp, "spec/test.ulaw")
      sleep 1.second
      dumper.bytes.should eq(67500)

      # send BYE
      bye_request = SIPUtils::Network::SIP::Request.new("BYE", "sip:bob@example.com", "SIP/2.0")
      bye_request.headers["Via"] = "SIP/2.0/UDP #{uac.host}:#{uac.port};branch=z9hG4bK776asdhj"
      bye_request.headers["From"] = "Alice <sip:alice@example.com>;tag=12345"
      bye_request.headers["To"] = "Bob <sip:bob@example.com>;tag=67890"
      bye_request.headers["Call-ID"] = "1234567890@example.com"
      bye_request.headers["CSeq"] = "2 BYE"
      bye_request.headers["Content-Length"] = "0"
      uac.send(bye_request)

      sleep 0.1.seconds
      audio_fork.has_media_server_for_call_id?(request.headers["Call-ID"]).should be_false
      # check BYE response
      response = uac.recv
      response.status_code.should eq(200)
    end
  end
end
