<script>
  import { m } from '#lib/paraglide/messages.js';
  import NextAction from '#lib/v2/components/NextAction.svelte';
</script>

<NextAction label={m.common_admins_only()} text={m.app_automation_admins_only_text()} />
