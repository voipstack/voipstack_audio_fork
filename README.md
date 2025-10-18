# voipstack_audio_fork

SIP proxy that forks RTP audio streams to multiple outputs (files, WebSocket, etc).

## Features

* Acts as a SIP proxy between PBX and endpoints
* Captures and dumps RTP audio streams
* Support for PCMU codec
* Configurable output destinations

## Installation

```sh
shards install
shards build
```

## Usage

### Basic Usage

```sh
./bin/voipstack_audio_fork -s sip://pbx_host:5080 -l 0.0.0.0 -p 5060 -o raw:///tmp/audio.ulaw
```

### CLI Options

* `-s, --pbx=URL` - PBX URL (e.g., sip://192.168.1.100:5080)
* `-l, --listen=HOST` - Listen host (default: 127.0.0.1)
* `-p, --port=PORT` - Listen port (default: 5060)
* `-o, --output FILE` - Output destination (format: raw://path)
* `-h, --help` - Display help message

### Example Setup

Forward SIP traffic from port 5060 to PBX at 192.168.1.10:5080 and dump audio:

```sh
./bin/voipstack_audio_fork \
  -s sip://192.168.1.10:5080 \
  -l 172.15.238.1 \
  -p 5060 \
  -o raw:///var/audio/call.ulaw
```

#### Freeswitch Usage

Test with playback.

```
freeswitch@096f2ec85864> originate sofia/internal/voipstack@172.15.238.1:5060 &playback(/etc/freeswitch/audios/stones-karaoke.wav)
```

## Library Usage

```crystal
require "voipstack_audio_fork"

class CustomDumper < VoipstackAudioFork::MediaDumper
  def start(session_id : String)
    # Initialize session
  end

  def dump(session_id : String, data : Bytes)
    # Process RTP data
  end

  def stop(session_id : String)
    # Cleanup session
  end
end

server = VoipstackAudioFork::Server.new
server.bind_pair("0.0.0.0", 5060, "pbx.example.com", 5080)
server.attach_dumper(CustomDumper.new)
server.listen
```

## Architecture

* `VoipstackAudioFork::Server` - Main SIP proxy server
* `VoipstackAudioFork::MediaDumper` - Abstract base for audio processors
* Handles SIP INVITE, ACK, and BYE methods
* Dynamically spawns UDP servers for each RTP session

## Caveats

* Only supports PCMU codec
* Single call recording per session

## Development

```sh
crystal spec
crystal tool format
```

## Contributing

1. Fork it (<https://github.com/bit4bit/voipstack_audio_fork/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT

## Contributors

- [Jovany Leandro G.C](https://github.com/bit4bit) - creator and maintainer
