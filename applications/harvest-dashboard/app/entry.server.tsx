import { PassThrough } from 'node:stream';
import { createReadableStreamFromReadable } from '@react-router/node';
import { renderToPipeableStream } from 'react-dom/server';
import { ServerRouter, type EntryContext } from 'react-router';

// The loader resolves the dashboard before rendering; no bot-specific streaming is needed.
export default function handleRequest(request: Request, status: number, headers: Headers, context: EntryContext) {
  return new Promise<Response>((resolve, reject) => {
    let shellRendered = false;
    const stream = renderToPipeableStream(<ServerRouter context={context} url={request.url} />, {
      onAllReady() {
        shellRendered = true;
        const body = new PassThrough();
        headers.set('Content-Type', 'text/html; charset=utf-8');
        headers.set('Cache-Control', 'no-store');
        resolve(new Response(createReadableStreamFromReadable(body), { status, headers }));
        stream.pipe(body);
      },
      onShellError: reject,
      onError() { status = 500; if (shellRendered) console.error('Page rendering failed.'); },
    });
    const timer = setTimeout(() => stream.abort(), 10_000);
    timer.unref();
  });
}
