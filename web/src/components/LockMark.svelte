<script>
  // The signature mark: a friendly monoline padlock + keyhole. Inherits
  // currentColor, so it takes the accent wherever it's placed.
  export let size = 40;
  export let stroke = 3;
</script>

<svg
  class="lockmark"
  width={size}
  height={size}
  viewBox="0 0 48 48"
  fill="none"
  aria-hidden="true"
>
  <!-- shackle -->
  <path
    d="M15 22 v-4.5 a9 9 0 0 1 18 0 V22"
    stroke="currentColor"
    stroke-width={stroke}
    stroke-linecap="round"
  />
  <!-- body -->
  <rect
    x="9"
    y="22"
    width="30"
    height="18"
    rx="6.5"
    stroke="currentColor"
    stroke-width={stroke}
  />
  <!-- keyhole -->
  <circle cx="24" cy="29.5" r="2.4" fill="currentColor" />
  <path
    d="M24 31.4 V35"
    stroke="currentColor"
    stroke-width={stroke}
    stroke-linecap="round"
  />
</svg>

<style>
  .lockmark {
    display: block;
  }
</style>
