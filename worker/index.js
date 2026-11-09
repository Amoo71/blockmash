export class RoomRelay {
  constructor(state) { this.state = state; }
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname !== "/connect") return new Response("Not found", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("WebSocket required", { status: 426 });
    const role = url.searchParams.get("role");
    if (role !== "sender" && role !== "receiver") return new Response("Invalid role", { status: 400 });
    const activePeers = this.state.getWebSockets();
    if (activePeers.some(peer => peer.deserializeAttachment()?.role === role)) {
      return new Response("A peer with this role is already connected to the room", { status: 409 });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();
    server.serializeAttachment({ role });
    server.addEventListener("message", event => {
      if (typeof event.data === "string") {
        if (event.data.length > 8192) { server.close(1009, "Message too large"); return; }
        for (const peer of this.state.getWebSockets()) {
          if (peer !== server && peer.readyState === WebSocket.OPEN) peer.send(event.data);
        }
        return;
      }
      const data = event.data;
      const size = data instanceof ArrayBuffer ? data.byteLength : data.size;
      if (role !== "sender" || size > 1800000) { server.close(1009, "Frame too large or wrong role"); return; }
      for (const peer of this.state.getWebSockets()) {
        if (peer !== server && peer.readyState === WebSocket.OPEN) {
          try { peer.send(data); } catch (_) {}
        }
      }
    });
    server.addEventListener("close", () => {});
    return new Response(null, { status: 101, webSocket: client });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/ws/")) return new Response("SwitchMirror relay is running", { headers: { "content-type": "text/plain; charset=utf-8" } });
    const room = url.pathname.slice(4);
    if (!/^\d{6}$/.test(room)) return new Response("Room code must contain six digits", { status: 400 });
    const id = env.ROOMS.idFromName(room);
    const stub = env.ROOMS.get(id);
    const target = new URL(request.url);
    target.pathname = "/connect";
    return stub.fetch(new Request(target, request));
  }
};
