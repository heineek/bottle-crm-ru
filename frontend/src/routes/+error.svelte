<script>
  import '../app.css';
  import { page } from '$app/state';
  import ErrorPage from '#lib/components/ErrorPage.svelte';
  import { m } from '#lib/paraglide/messages.js';
</script>

<svelte:head>
  <title
    >{page.status}
    {page.status === 404 ? m.app_error_title_not_found() : m.app_error_title_error()} | BottleCRM</title
  >
</svelte:head>

<main class="bg-background min-h-screen">
  <ErrorPage status={page.status} message={page.error?.message ?? ''} />
</main>
