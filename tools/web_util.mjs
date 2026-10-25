// Shared by the Playwright checks: a static server for a web export and a
// headless Chrome that can render it (SwiftShader WebGL).
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { chromium } from 'playwright';

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml',
};

// Serves buildDir on a free localhost port; resolves to { server, url } (url of index.html).
export async function serveBuild(buildDir) {
  const server = createServer(async (req, res) => {
    const path = resolve(buildDir, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
    if (path !== buildDir && !path.startsWith(buildDir + sep)) {
      res.writeHead(403).end();
      return;
    }
    try {
      const body = await readFile(path);
      res.writeHead(200, { 'Content-Type': MIME[extname(path)] ?? 'application/octet-stream' }).end(body);
    } catch (err) {
      console.error(`[server] ${req.url}: ${err.code ?? err.message}`);
      res.writeHead(404).end();
    }
  });
  await new Promise((ok, fail) => server.once('error', fail).listen(0, '127.0.0.1', ok));
  return { server, url: `http://127.0.0.1:${server.address().port}/index.html` };
}

export function launchChrome() {
  return chromium.launch({
    channel: 'chrome',
    headless: true,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
}
