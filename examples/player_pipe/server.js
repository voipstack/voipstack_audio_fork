import { serve } from "bun";
import { WebSocketServer } from "ws";

console.log("🚀 Starting RTP Audio Server...");

// Serve website and player.js
serve({
  fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/") {
      const html =
        "<!DOCTYPE html>\n" +
        "<html>\n" +
        "<head>\n" +
        "  <meta charset='UTF-8'>\n" +
        "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>\n" +
        "  <title>RTP PCMU Audio Player</title>\n" +
        "  <style>\n" +
        "    body {\n" +
        "      font-family: Arial, sans-serif;\n" +
        "      max-width: 800px;\n" +
        "      margin: 50px auto;\n" +
        "      padding: 20px;\n" +
        "    }\n" +
        "    button {\n" +
        "      padding: 10px 20px;\n" +
        "      margin: 5px;\n" +
        "      font-size: 16px;\n" +
        "      cursor: pointer;\n" +
        "    }\n" +
        "    #status {\n" +
        "      margin-top: 20px;\n" +
        "      padding: 10px;\n" +
        "      background: #f0f0f0;\n" +
        "      border-radius: 5px;\n" +
        "    }\n" +
        "  </style>\n" +
        "</head>\n" +
        "<body>\n" +
        "  <h1>RTP PCMU Audio Player</h1>\n" +
        "  <div>\n" +
        "    <button id='play'>▶ Play</button>\n" +
        "    <button id='stop'>⏹ Stop</button>\n" +
        "  </div>\n" +
        "  <div id='status'>\n" +
        "    <strong>Status:</strong> Ready<br>\n" +
        "    Open browser console (F12) for detailed logs\n" +
        "  </div>\n" +
        "  <script src='/player.js'></script>\n" +
        "</body>\n" +
        "</html>\n";
      return new Response(html, {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
        },
      });
    }

    if (url.pathname === "/player.js") {
      return new Response(Bun.file(import.meta.dir + "/player.js"), {
        headers: { "Content-Type": "application/javascript" },
      });
    }

    return new Response("Not found", { status: 404 });
  },
  port: 3000,
});

console.log("✅ HTTP Server running on http://localhost:3000");

// WebSocket for browser clients (audio out)
const wssOut = new WebSocketServer({ port: 3001 });
let connectedClients = 0;

wssOut.on("connection", (client) => {
  connectedClients++;
  console.log(`🎧 Browser client connected (total: ${connectedClients})`);

  client.on("close", () => {
    connectedClients--;
    console.log(`👋 Browser client disconnected (total: ${connectedClients})`);
  });

  client.on("error", (err) => {
    console.error("❌ Browser client error:", err.message);
  });
});

console.log("✅ WebSocket server for browsers running on ws://localhost:3001");

// WebSocket for incoming audio from proxy (audio in)
const wssIn = new WebSocketServer({ port: 3002 });
let proxyConnected = false;
let packetCount = 0;
let lastStatsTime = Date.now();

wssIn.on("connection", (wsIn) => {
  proxyConnected = true;
  packetCount = 0;
  console.log("📡 Proxy connected on port 3002");

  wsIn.on("message", (data) => {
    packetCount++;

    // Log stats every 100 packets
    if (packetCount % 100 === 0) {
      const now = Date.now();
      const elapsed = (now - lastStatsTime) / 1000;
      const packetsPerSec = 100 / elapsed;
      console.log(
        `📊 Received ${packetCount} packets (${packetsPerSec.toFixed(1)} pkt/s)`,
      );
      lastStatsTime = now;
    }

    // Forward immediately to all connected browser clients
    let forwarded = 0;
    wssOut.clients.forEach((client) => {
      if (client.readyState === 1) {
        // WebSocket.OPEN
        client.send(data, { binary: true });
        forwarded++;
      }
    });

    // Log warning if no clients are connected
    if (forwarded === 0 && packetCount % 50 === 0) {
      console.warn("⚠️  No browser clients connected to receive audio");
    }
  });

  wsIn.on("close", () => {
    proxyConnected = false;
    console.log("📡 Proxy disconnected");
  });

  wsIn.on("error", (err) => {
    console.error("❌ Proxy connection error:", err.message);
  });
});

console.log("✅ WebSocket server for proxy running on ws://localhost:3002");
console.log("\n" + "=".repeat(60));
console.log("Ready! Connect your proxy to ws://localhost:3002");
console.log("Open http://localhost:3000 in your browser");
console.log("=".repeat(60) + "\n");

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\n🛑 Shutting down...");
  wssOut.close();
  wssIn.close();
  process.exit(0);
});
