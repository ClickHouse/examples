export function enforceOrigin(request: Request) {
  const configured = process.env.APP_ORIGIN;
  if (!configured) throw new Error('APP_ORIGIN is required.');
  const expected = new URL(configured);
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(expected.hostname) || expected.pathname !== '/' || expected.search || expected.hash) throw new Error('This trusted-operator example requires a loopback APP_ORIGIN.');
  if (new URL(request.url).origin !== expected.origin) throw new Response('Use the configured local application address.', { status: 403 });
  if (request.method !== 'GET' && request.method !== 'HEAD' && request.headers.get('Origin') !== expected.origin) {
    throw new Response('This form must be submitted from the local garden journal.', { status: 403 });
  }
}
