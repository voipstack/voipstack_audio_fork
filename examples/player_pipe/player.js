const ws = new WebSocket("ws://localhost:3001");
const RTP_HEADER_SIZE = 12;
const SAMPLE_RATE = 8000;
const JITTER_BUFFER_TARGET = 3; // Start playing with just 3 packets
const JITTER_BUFFER_MAX = 150;
const PACKET_TOLERANCE = 10; // Allow gaps when checking for "enough data"

// --- µ-law to linear ---
function ulawToLinear(ulawByte) {
  ulawByte = ~ulawByte;
  let sign = ulawByte & 0x80 ? -1 : 1;
  let exponent = (ulawByte >> 4) & 0x07;
  let mantissa = ulawByte & 0x0f;
  let sample = ((mantissa << 1) + 33) << (exponent + 2);
  return sign * (sample - 132);
}

// --- Helper: Handle sequence number wraparound ---
function seqDiff(a, b) {
  const diff = a - b;
  if (diff > 32768) return diff - 65536;
  if (diff < -32768) return diff + 65536;
  return diff;
}

// --- Jitter buffer ---
class JitterBuffer {
  constructor() {
    this.packets = new Map();
    this.nextExpectedSeq = null;
    this.initialized = false;
    this.stats = { received: 0, played: 0, lost: 0, rejected: 0 };
    this.lastPushTime = 0;
  }

  push(data) {
    if (data.length <= RTP_HEADER_SIZE) return;

    const seq = (data[2] << 8) | data[3];
    const now = Date.now();
    this.stats.received++;

    // Detect burst arrivals
    if (now - this.lastPushTime > 100) {
      console.log(`Burst detected: ${this.packets.size} packets buffered`);
    }
    this.lastPushTime = now;

    // Initialize on first packet
    if (!this.initialized) {
      this.nextExpectedSeq = seq;
      this.initialized = true;
      this.packets.clear();
      console.log(`Initialized with seq=${seq}`);
    }

    // Store packet (avoid duplicates)
    if (!this.packets.has(seq)) {
      this.packets.set(seq, data);
    }

    // If buffer is getting too large, we're not consuming fast enough
    if (this.packets.size > JITTER_BUFFER_MAX) {
      this.handleOverflow(seq);
    }
  }

  handleOverflow(latestSeq) {
    console.warn(
      `Buffer overflow! size=${this.packets.size}, latest seq=${latestSeq}`,
    );

    // Find the oldest packet still in buffer
    let minSeq = latestSeq;
    for (const seq of this.packets.keys()) {
      if (seqDiff(seq, minSeq) < 0) {
        minSeq = seq;
      }
    }

    // Jump to oldest packet in buffer (we'll catch up naturally)
    console.log(`Jumping from seq=${this.nextExpectedSeq} to seq=${minSeq}`);
    this.stats.lost += Math.abs(seqDiff(minSeq, this.nextExpectedSeq));
    this.nextExpectedSeq = minSeq;

    // Remove very old packets
    this.trimOldPackets();
  }

  trimOldPackets() {
    const toDelete = [];
    for (const [seq] of this.packets) {
      const offset = seqDiff(seq, this.nextExpectedSeq);
      if (offset < -10) {
        toDelete.push(seq);
      }
    }
    toDelete.forEach((seq) => this.packets.delete(seq));
    if (toDelete.length > 0) {
      console.log(`Trimmed ${toDelete.length} old packets`);
    }
  }

  hasEnoughData() {
    if (!this.initialized || this.packets.size === 0) return false;

    // Check if we have at least TARGET packets in a small window
    let count = 0;
    let seq = this.nextExpectedSeq;

    // Look ahead with tolerance for gaps
    for (let i = 0; i < PACKET_TOLERANCE; i++) {
      if (this.packets.has(seq)) {
        count++;
        if (count >= JITTER_BUFFER_TARGET) {
          return true;
        }
      }
      seq = (seq + 1) & 0xffff;
    }

    return false;
  }

  pop() {
    if (!this.initialized) return null;

    const data = this.packets.get(this.nextExpectedSeq);

    if (data) {
      this.packets.delete(this.nextExpectedSeq);
      this.nextExpectedSeq = (this.nextExpectedSeq + 1) & 0xffff;
      this.stats.played++;
      return data;
    }

    // Packet loss - try to find next available packet
    this.stats.lost++;

    for (let i = 1; i <= 10; i++) {
      const nextSeq = (this.nextExpectedSeq + i) & 0xffff;
      if (this.packets.has(nextSeq)) {
        if (i > 1) {
          console.warn(`Skipped ${i} missing packets`);
        }
        this.nextExpectedSeq = nextSeq;
        return this.pop(); // Recursive call
      }
    }

    // No packets found - return silence and advance
    this.nextExpectedSeq = (this.nextExpectedSeq + 1) & 0xffff;
    return this.createSilencePacket();
  }

  createSilencePacket() {
    const silentPayload = new Uint8Array(160);
    silentPayload.fill(0xff); // µ-law silence

    const packet = new Uint8Array(RTP_HEADER_SIZE + 160);
    packet.set(silentPayload, RTP_HEADER_SIZE);

    return packet;
  }

  reset() {
    this.packets.clear();
    this.nextExpectedSeq = null;
    this.initialized = false;
    this.stats = { received: 0, played: 0, lost: 0, rejected: 0 };
  }

  getStats() {
    return {
      ...this.stats,
      buffered: this.packets.size,
      nextExpected: this.nextExpectedSeq,
    };
  }
}

// --- GLOBALS ---
let audioCtx;
let jitterBuffer = new JitterBuffer();
let isPlaying = false;
let nextPlayTime = 0;
let scheduleInterval = null;
let statsInterval = null;

// --- PLAY BUTTON ---
document.getElementById("play").onclick = () => {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)({
      sampleRate: SAMPLE_RATE,
    });
  }

  if (!isPlaying) {
    isPlaying = true;
    nextPlayTime = audioCtx.currentTime + 0.1; // Small initial delay
    startScheduler();
    startStatsLogger();
    console.log("Playback started");
  }
};

// --- STOP BUTTON ---
const stopBtn = document.getElementById("stop");
if (stopBtn) {
  stopBtn.onclick = () => {
    isPlaying = false;
    if (scheduleInterval) {
      clearInterval(scheduleInterval);
      scheduleInterval = null;
    }
    if (statsInterval) {
      clearInterval(statsInterval);
      statsInterval = null;
    }
    jitterBuffer.reset();
    console.log("Playback stopped");
  };
}

// --- STATS LOGGER ---
function startStatsLogger() {
  if (statsInterval) clearInterval(statsInterval);

  statsInterval = setInterval(() => {
    const stats = jitterBuffer.getStats();
    console.log(
      `📊 Stats: received=${stats.received}, played=${stats.played}, lost=${stats.lost}, buffered=${stats.buffered}`,
    );
  }, 3000);
}

// --- SCHEDULER ---
function startScheduler() {
  if (scheduleInterval) clearInterval(scheduleInterval);

  scheduleInterval = setInterval(() => {
    if (!isPlaying) return;

    // Aggressively schedule chunks
    let scheduled = 0;
    const maxSchedule = 10;

    while (
      scheduled < maxSchedule &&
      nextPlayTime < audioCtx.currentTime + 0.5
    ) {
      if (jitterBuffer.hasEnoughData() || jitterBuffer.packets.size > 0) {
        if (scheduleAudioChunk()) {
          scheduled++;
        } else {
          break; // No more packets available
        }
      } else {
        break;
      }
    }

    if (scheduled > 0) {
      // console.log(
      //   `Scheduled ${scheduled} chunks, buffer has ${jitterBuffer.packets.size} packets`,
      // );
    }
  }, 20);
}

function scheduleAudioChunk() {
  if (!audioCtx) return false;

  // Force playback even without "enough" data if we have any packets
  const hasPackets = jitterBuffer.packets.size > 0;
  const hasEnough = jitterBuffer.hasEnoughData();

  if (!hasPackets && !hasEnough) {
    return false;
  }

  const data = jitterBuffer.pop();
  if (!data) return false;

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

  // Handle underrun
  if (nextPlayTime < audioCtx.currentTime) {
    console.warn("⚠️ Playback underrun, resyncing");
    nextPlayTime = audioCtx.currentTime + 0.05;
  }

  source.start(nextPlayTime);

  const chunkDuration = pcmData.length / SAMPLE_RATE;
  nextPlayTime += chunkDuration;

  return true;
}

// --- WEBSOCKET ---
ws.binaryType = "arraybuffer";

ws.onopen = () => {
  console.log("✅ WebSocket connected");
};

ws.onmessage = (event) => {
  const data = new Uint8Array(event.data);
  jitterBuffer.push(data);
};

ws.onerror = (error) => {
  console.error("❌ WebSocket error:", error);
};

ws.onclose = () => {
  console.log("🔌 WebSocket closed");
  isPlaying = false;
  if (scheduleInterval) clearInterval(scheduleInterval);
  if (statsInterval) clearInterval(statsInterval);
};
