#   Player Pipe Example
Play softswitch audio in the webbrowser.

1. `bun run examples/player_pipe/server.js`
2. `firefox http://localhost:3000`
3. `./bin/voipstack_audio_fork -s fs://172.15.238.10:5060 -l 172.15.238.1 -p 6565 -o ws://localhost:3002`
4. ` originate sofia/internal/voipstack@172.15.238.1:6565 &playback(/etc/freeswitch/audios/stones-karaoke.wav)`
