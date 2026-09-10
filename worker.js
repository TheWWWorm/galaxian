// Numbered asset streaming follows the Apache-2.0 DEEP remake hosting approach.
// A bounded manifest prevents a missing asset or SPA fallback becoming an endless stream.
import parts from './parts.json';
const types = {wasm: 'application/wasm', pck: 'application/octet-stream', js: 'text/javascript; charset=utf-8'};
function headersFor(headers = new Headers()) {
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Cache-Control', 'no-cache');
  return headers;
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol === 'http:' && url.hostname === 'galaxian.wwworm.com') {
      url.protocol = 'https:';
      return Response.redirect(url.href, 308);
    }
    const entry = parts[url.pathname];
    if (!entry) {
      const response = await env.ASSETS.fetch(request);
      return new Response(response.body, {status: response.status, headers: headersFor(new Headers(response.headers))});
    }
    const headers = headersFor();
    headers.set('Content-Type', types[url.pathname.split('.').pop()] || 'application/octet-stream');
    headers.set('Content-Length', String(entry.size));
    if (request.method === 'HEAD') return new Response(null, {headers});
    if (request.method !== 'GET') return new Response('Method not allowed', {status: 405, headers});
    let index = 0, reader = null;
    const body = new ReadableStream({
      async pull(controller) {
        try {
          while (true) {
            if (!reader) {
              if (index === entry.count) { controller.close(); return; }
              const response = await env.ASSETS.fetch(new URL(`${url.pathname}.part${index++}`, url.origin));
              if (!response.ok) throw new Error('Incomplete engine export');
              reader = response.body.getReader();
            }
            const chunk = await reader.read();
            if (!chunk.done) { controller.enqueue(chunk.value); return; }
            reader.releaseLock(); reader = null;
          }
        } catch (error) { controller.error(error); }
      },
      async cancel() { if (reader) await reader.cancel(); }
    });
    return new Response(body, {headers});
  }
};
