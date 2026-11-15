<script>
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import { goto } from '$app/navigation';
  import { Button } from '#lib/components/ui/button/index.js';
  import { ArrowLeft, Home, Compass, Users, Building2, BarChart3 } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';

  /**
   * @typedef {Object} Props
   * @property {number} [status]   HTTP status code
   * @property {string} [message]  Error message from the server (optional)
   * @property {boolean} [showQuickLinks]  Show the "Try one of these" panel (default true for 404)
   */

  /** @type {Props} */
  let { status = 404, message = '', showQuickLinks } = $props();

  let isNotFound = $derived(status === 404);
  let showLinks = $derived(showQuickLinks ?? isNotFound);

  let title = $derived.by(() => {
    if (isNotFound) return m.app_error_page_not_found();
    if (status === 403) return m.app_error_page_forbidden();
    if (status === 401) return m.app_error_page_sign_in();
    if (status >= 500) return m.app_error_page_server();
    return m.app_error_page_other();
  });

  let description = $derived.by(() => {
    if (message) return message;
    if (isNotFound) return m.app_error_page_not_found_body();
    if (status === 403) return m.app_error_page_forbidden_body();
    if (status === 401) return m.app_error_page_sign_in_body();
    if (status >= 500) return m.app_error_page_server_body();
    return m.app_error_page_other_body();
  });

  let quickLinks = $derived([
    { href: '/', label: m.app_error_link_dashboard(), icon: BarChart3 },
    { href: '/accounts', label: m.app_error_link_accounts(), icon: Building2 },
    { href: '/contacts', label: m.app_error_link_contacts(), icon: Users }
  ]);

  function goBack() {
    if (typeof history !== 'undefined' && history.length > 1) history.back();
    else goto(resolve(''));
  }
</script>

<div class="flex min-h-[80vh] w-full items-center justify-center px-6 py-16">
  <div class="w-full max-w-xl text-center">
    <!-- Stylized status code -->
    <div class="relative mb-6 flex items-center justify-center">
      <div
        class="bg-primary/10 absolute inset-0 mx-auto h-32 w-32 rounded-full blur-3xl"
        aria-hidden="true"
      ></div>
      <div class="relative">
        <span
          class="text-primary block text-[7rem] leading-none font-bold tracking-tighter md:text-[9rem]"
          style="font-feature-settings: 'tnum';"
        >
          {status}
        </span>
      </div>
    </div>

    <!-- Headline + supporting copy -->
    <h1 class="text-foreground mb-3 text-2xl font-semibold tracking-tight md:text-3xl">
      {title}
    </h1>
    <p class="text-muted-foreground mx-auto mb-8 max-w-md text-base leading-relaxed">
      {description}
    </p>

    <!-- Primary actions -->
    <div class="flex flex-col items-center justify-center gap-3 sm:flex-row">
      <Button onclick={() => goto(resolve(''))} class="gap-2">
        <Home class="h-4 w-4" />
        {m.app_error_go_dashboard()}
      </Button>
      <Button variant="outline" onclick={goBack} class="gap-2">
        <ArrowLeft class="h-4 w-4" />
        {m.app_error_go_back()}
      </Button>
    </div>

    <!-- Quick links (404 only by default) -->
    {#if showLinks}
      <div class="mt-12">
        <div class="mb-4 flex items-center justify-center gap-2">
          <Compass class="text-muted-foreground h-4 w-4" />
          <span class="text-muted-foreground text-xs font-medium tracking-wide uppercase">
            {m.app_error_try_these()}
          </span>
        </div>
        <div class="flex flex-wrap items-center justify-center gap-2">
          {#each quickLinks as link (link.href)}
            <a
              href={resolve(asInternalPath(link.href))}
              class="border-border/60 bg-background hover:border-primary/40 hover:bg-accent hover:text-foreground text-muted-foreground inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors"
            >
              <link.icon class="h-3.5 w-3.5" />
              {link.label}
            </a>
          {/each}
        </div>
      </div>
    {/if}
  </div>
</div>
