const ws = new WebSocket("ws://localhost:3001");

const RTP_HEADER_SIZE = 12;
const SAMPLE_RATE = 8000;
const PLAY_CHUNK_SIZE = 160;
const JITTER_BUFFER_TARGET = 5;
const JITTER_BUFFER_MAX = 20;

function ulawToLinear(ulawByte) {
  ulawByte = ~ulawByte;
  let sign = ulawByte & 0x80 ? -1 : 1;
  let exponent = (ulawByte >> 4) & 0x07;
  let mantissa = ulawByte & 0x0f;
  let sample = ((mantissa << 1) + 33) << (exponent + 2);
  return sign * (sample - 132);
}

class JitterBuffer {
  constructor() {
    this.packets = new Map();
    this.baseSequence = null;
    this.playIndex = 0;
  }

  push(data) {
    if (data.length <= RTP_HEADER_SIZE) return;

    const seq = (data[2] << 8) | data[3];

    if (this.baseSequence === null) {
      this.baseSequence = seq;
      this.playIndex = 0;
      this.packets.clear();
      return;
    }

    const relativeIndex = seq - this.baseSequence;

    if (relativeIndex < 0) {
      return;
    }

    if (relativeIndex > JITTER_BUFFER_MAX * 10) {
      this.reset(seq);
      return;
    }

    if (this.packets.has(relativeIndex)) {
      return;
    }

    this.packets.set(relativeIndex, data);

    if (this.packets.size > JITTER_BUFFER_MAX) {
      this.trim();
    }
  }

  trim() {
    while (this.playIndex > 0 && this.packets.size > JITTER_BUFFER_MAX) {
      this.packets.delete(this.playIndex);
      this.playIndex--;
    }
  }

  hasEnoughData() {
    return this.packets.size >= JITTER_BUFFER_TARGET;
  }

  pop() {
    if (this.packets.size === 0) return null;

    const data = this.packets.get(this.playIndex);
    this.packets.delete(this.playIndex);
    this.playIndex++;
    return data;
  }

  reset(seq) {
    this.packets.clear();
    this.baseSequence = seq;
    this.playIndex = 0;
  }
}

let audioCtx;
let jitterBuffer = new JitterBuffer();
let isPlaying = false;
let nextPlayTime = 0;
let scheduleInterval = null;

document.getElementById("play").onclick = () => {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  if (!isPlaying) {
    isPlaying = true;
    nextPlayTime = audioCtx.currentTime + 0.05;
    startScheduler();
  }
};

function startScheduler() {
  if (scheduleInterval) clearInterval(scheduleInterval);
  scheduleInterval = setInterval(() => {
    if (!isPlaying) return;
    scheduleAudioChunk();
  }, 10);
}

function scheduleAudioChunk() {
  if (!audioCtx) return;

  if (!jitterBuffer.hasEnoughData()) {
    return;
  }

  const data = jitterBuffer.pop();
  if (!data) return;

  const pcmuPayload = data.slice(RTP_HEADER_SIZE);
  const pcmData = new Float32Array(pcmuPayload.length);

  for (let i = 0; i < pcmuPayload.length; i++) {
    pcmData[i] = ulawToLinear(pcmuPayload[i]) / 32768;
  }

  const buffer = audioCtx.createBuffer(1, pcmData.length, SAMPLE_RATE);
  buffer.getChannelData(0).set(pcmData);

  const source = audioCtx.createBufferSource();
  source.buffer = buffer;
  source.connect(audioCtx.destination);

  if (nextPlayTime < audioCtx.currentTime) {
    nextPlayTime = audioCtx.currentTime + 0.01;
  }

  source.start(nextPlayTime);

  const chunkDuration = PLAY_CHUNK_SIZE / SAMPLE_RATE;
  nextPlayTime += chunkDuration;
}

ws.binaryType = "arraybuffer";

ws.onmessage = (event) => {
  const data = new Uint8Array(event.data);
  jitterBuffer.push(data);
};
