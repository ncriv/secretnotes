<script>
  import { vault } from './lib/store.js';
  import Login from './components/Login.svelte';
  import Workspace from './components/Workspace.svelte';
</script>

{#if $vault}
  <Workspace />
{:else}
  <Login />
{/if}
