import type { Handle } from '@sveltejs/kit';
export const handle: Handle = async ({ event, resolve }) => {
  const origin = process.env.ORIGIN;
  if (!origin || !['127.0.0.1', 'localhost', '[::1]'].includes(new URL(origin).hostname))
    return new Response(
      'Configure a loopback ORIGIN for this trusted-operator example.',
      { status: 503 },
    );
  if (
    event.request.headers.get('host') !== new URL(origin).host ||
    event.url.origin !== origin ||
    (!['GET', 'HEAD'].includes(event.request.method) &&
      event.request.headers.get('origin') !== origin)
  )
    return new Response('Use the configured local supplier intake address.', {
      status: 403,
    });
  const response = await resolve(event);
  response.headers.set('cache-control', 'no-store');
  return response;
};
