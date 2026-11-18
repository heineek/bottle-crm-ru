import { json } from '@sveltejs/kit';
import { searchLinkTargets } from '#lib/server/v2/custom-objects.js';
import { m } from '#lib/paraglide/messages.js';
import type { RequestHandler } from './$types';

/**
 * The link picker's search. The session token is an httpOnly cookie, so the
 * browser asks here; the API still decides what the caller may open.
 */
export const GET: RequestHandler = async ({ url, cookies }) => {
  if (!cookies.get('jwt_access'))
    return json({ error: m.app_api_not_signed_in() }, { status: 401 });
  const target = url.searchParams.get('target') ?? '';
  const q = (url.searchParams.get('q') ?? '').trim().slice(0, 100);
  try {
    const matches = await searchLinkTargets({ cookies }, target, q);
    return json(matches, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch {
    return json({ error: m.app_api_search_could_not() }, { status: 502 });
  }
};
