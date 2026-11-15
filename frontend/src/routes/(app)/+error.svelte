<script>
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { isOrgAdmin } from '#lib/admin.js';
  import { labelOf } from '#lib/v2/modules.js';
  import { asInternalPath } from '#lib/utils/paths.js';
  import { FileQuestion, Lock, ToggleLeft, TriangleAlert } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';

  /**
   * Every failed load in /v2 lands here. Four cases, four different things
   * to do next, which is the point: "Something went wrong" tells you nothing
   * and leaves you on a dead page.
   *
   * 403 deliberately does not say whether the record exists. Confirming that
   * an id is real to somebody who cannot open it is an information leak, so
   * the copy talks about access, never about the record.
   */
  let status = $derived(page.status);
  let moduleOff = $derived(page.error?.code === 'module_off');
  // The API's refusal names the module but not its label, which follows terminology.
  let moduleLabel = $derived(
    page.error?.label || (page.error?.module ? labelOf(page.data.modules, page.error.module) : '')
  );

  let shape = $derived(
    moduleOff
      ? {
          icon: ToggleLeft,
          title: moduleLabel
            ? m.app_error_module_off({ module: moduleLabel })
            : m.app_error_module_off_generic(),
          body: page.error?.message ?? ''
        }
      : status === 404
        ? {
            icon: FileQuestion,
            title: m.app_error_not_found_title(),
            body: page.error?.message || m.app_error_not_found_body()
          }
        : status === 403
          ? {
              icon: Lock,
              title: m.app_error_forbidden_title(),
              body: m.app_error_forbidden_body()
            }
          : {
              icon: TriangleAlert,
              title: m.app_error_server_title(),
              body: page.error?.message || m.app_error_server_body()
            }
  );
</script>

<div class="v2-scroll">
  <EmptyState title={shape.title} body={shape.body}>
    {#snippet icon()}
      <shape.icon size={21} />
    {/snippet}
    {#snippet actions()}
      {#if status >= 500 && !moduleOff}
        <button class="v2-btn v2-btn-primary" onclick={() => location.reload()}
          >{m.common_try_again()}</button
        >
      {/if}
      <a class="v2-btn" href={resolve('')}>{m.app_error_back_today()}</a>
      {#if moduleOff && isOrgAdmin(page.data)}
        <a class="v2-btn" href={resolve(asInternalPath('/settings/modules'))}
          >{m.app_error_open_modules()}</a
        >
      {/if}
    {/snippet}
  </EmptyState>

  <p class="v2-sub" style="text-align:center;font-size:11.5px">
    <span class="v2-num">{status}</span>
    · {page.url.pathname}
  </p>
</div>
