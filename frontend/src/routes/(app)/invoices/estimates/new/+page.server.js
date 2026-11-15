import { fail, redirect } from '@sveltejs/kit';
import { listAccounts } from '#lib/server/v2/accounts.js';
import { listContacts } from '#lib/server/v2/contacts.js';
import { listDeals } from '#lib/server/v2/deals.js';
import { listProducts } from '#lib/server/v2/products.js';
import { createEstimate, estimateFromDeal } from '#lib/server/v2/estimates.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { getNumbering } from '#lib/server/v2/organization.js';
import { getModules } from '#lib/server/v2/modules.js';
import { isOn } from '#lib/v2/modules.js';
import { m } from '#lib/paraglide/messages.js';

/**
 * The estimate builder's pickers, the same list layers the invoice builder
 * reads, plus the deals for the optional deal link. Every list is what the API
 * lets this caller see, and the API checks each id again on save.
 *
 * `?opportunity=<id>` (the "Create estimate" action on a deal) prefills the
 * form from that deal; a deal the caller cannot open prefills nothing. The
 * org's numbering format feeds the "Assigned on save" preview.
 *
 * @type {import('./$types').PageServerLoad}
 */
export async function load({ cookies, locals, url }) {
  // Asked directly: `parent()` would rerun the whole shell load.
  const modulesP = getModules({ cookies, locals });
  const dealsOnP = modulesP.then((m) => isOn(m?.modules ?? null, 'deals'));
  const requested = url.searchParams.get('opportunity');
  const [accounts, contacts, products, deals, prefill, numbering] = await Promise.all([
    listAccounts({ cookies }, new URLSearchParams({ limit: '1000' })),
    listContacts({ cookies }, new URLSearchParams({ limit: '1000' })),
    listProducts({ cookies }),
    // A failed deal list costs the optional deal picker, not the form.
    dealsOnP.then((on) =>
      on
        ? listDeals({ cookies }, new URLSearchParams({ limit: '1000' })).catch(() => ({
            results: []
          }))
        : { results: [] }
    ),
    requested
      ? dealsOnP.then((on) => (on ? estimateFromDeal({ cookies }, requested) : null))
      : null,
    getNumbering({ cookies })
  ]);

  return {
    modules: (await modulesP)?.modules ?? null,
    accounts: accounts.results.map((a) => ({
      id: a.id,
      name: a.name || m.invoices_unnamed_account()
    })),
    contacts: contacts.results.map((c) => ({
      id: c.id,
      name: c.name || c.email || m.invoices_unnamed_contact(),
      account_id: c.account?.id ?? null,
      account_name: c.account?.name ?? ''
    })),
    products: products.results
      .filter((p) => p.is_active)
      .map((p) => ({ id: p.id, name: p.name, sku: p.sku, price: p.price })),
    deals: deals.results.map((d) => ({ id: d.id, name: d.name, account_id: d.account.id })),
    prefill,
    numbering
  };
}

/** @type {import('./$types').Actions} */
export const actions = {
  /**
   * Create the draft from the builder's one JSON `payload` field. The server
   * owns org, creator, number, token, totals and status, and decides whether
   * this caller may bill the account and cite the deal.
   */
  create: async ({ cookies, request }) => {
    const form = await request.formData();
    let body;
    try {
      body = JSON.parse(form.get('payload')?.toString() || '{}');
    } catch {
      return fail(400, { error: m.invoices_estimate_form_unreadable() });
    }

    if (!body.account_id) return fail(400, { error: m.invoices_recurring_choose_account() });
    if (!body.contact_id) return fail(400, { error: m.invoices_recurring_choose_contact() });
    if (!body.title) return fail(400, { error: m.invoices_estimate_title_required() });
    if (!Array.isArray(body.line_items) || body.line_items.length === 0) {
      return fail(400, { error: m.invoices_lines_required() });
    }

    try {
      await createEstimate({ cookies }, body);
    } catch (/** @type {any} */ err) {
      return fail(err?.status === 403 ? 403 : 400, {
        error: readableError(err, m.invoices_estimate_create_failed())
      });
    }

    // There is no estimate detail page on the web; the worklist is where a
    // new draft is sent from.
    redirect(303, '/invoices/estimates');
  }
};
