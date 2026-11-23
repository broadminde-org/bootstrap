---
name: svelte-core-bestpractices
description: >-
  Svelte 5 runes-mode best practices — $state, $derived, $effect, $props,
  events, snippets, keyed each blocks, scoped styling, context, and async
  Svelte, with version-aware alternatives for new runes-mode work. USE FOR
  writing or reviewing Svelte 5 components. Preserve valid stores/actions
  and existing component modes; not a conversion or upgrade mandate.
  DO NOT USE FOR Svelte 4 or earlier.
---

# Svelte Core Best Practices

## Version And Scope

Use `svelte-code-writer` for the authorized documentation/autofixer workflow
when available. Keep the portable minimum here: inspect project metadata,
lockfile, installed Svelte version, component mode, and compiler configuration
before choosing APIs. Do not assume a package range is the installed version,
upgrade dependencies, enable async, or convert existing components merely to
follow this skill. Read only relevant bundled/official reference sections.
Autofixer plus applicable project checks remain required for component edits
under execution authority; report denied/unavailable validation explicitly.

| API | Minimum Svelte Version | Supported Older-Version Choice |
|---|---|---|
| Override a `let` derived value | 5.25 | Keep derived read-only; separate explicit state if needed |
| `{@attach ...}` / `svelte/attachments` | 5.29 | `use:action` with its existing lifecycle |
| `createContext` | 5.40 | Typed `getContext` / `setContext` with a shared key |
| Component await expressions | 5.36 plus existing `experimental.async` | Existing async event/load logic and `{#await}` blocks |
| Function bindings | 5.9 | Supported bindings/event handlers |
| `$inspect.trace` | 5.14 | Existing debugging tools / `$inspect` |
| Array/object `class` values | 5.16 | String `class` or `class:` directives |

Official sources (verified 2026-11-23): [derived overrides](https://svelte.dev/docs/svelte/$derived#Overriding-derived-values), [attachments](https://svelte.dev/docs/svelte/@attach), [createContext](https://svelte.dev/docs/svelte/svelte#createContext), [await expressions](https://svelte.dev/docs/svelte/await-expressions), [bindings](https://svelte.dev/docs/svelte/bind#Function-bindings), [inspect](https://svelte.dev/docs/svelte/$inspect), and [classes](https://svelte.dev/docs/svelte/class). Current documentation may include still newer APIs: verify each affected one against the project's supported version.

## `$state`

Only use the `$state` rune for variables that should be _reactive_ — in other words, variables that cause an `$effect`, `$derived` or template expression to update. Everything else can be a normal variable.

Objects and arrays (`$state({...})` or `$state([...])`) are made deeply reactive, meaning mutation will trigger updates. This has a trade-off: in exchange for fine-grained reactivity, the objects must be proxied, which has performance overhead. In cases where you're dealing with large objects that are only ever reassigned (rather than mutated), use `$state.raw` instead. This is often the case with API responses, for example.

## `$derived`

To compute something from state, use `$derived` rather than `$effect`:

```js
// do this
let square = $derived(num * num);

// don't do this
let square;

$effect(() => {
	square = num * num;
});
```

> [!NOTE] `$derived` is given an expression, _not_ a function. If you need to use a function (because the expression is complex, for example) use `$derived.by`.

Since Svelte 5.25, a derived declared with `let` can be temporarily overridden by
assignment; dependency changes cause recalculation. Before 5.25 deriveds are
read-only, and `const` derived declarations cannot be reassigned.

If the derived expression is an object or array, it will be returned as-is — it is _not_ made deeply reactive. You can, however, use `$state` inside `$derived.by` in the rare cases that you need this.

## `$effect`

Effects are an escape hatch and should mostly be avoided. In particular, avoid updating state inside effects.

- If you need to sync state to an external library such as D3, consider [`{@attach ...}`](references/attach.md) on 5.29+ when appropriate; `use:action` remains valid, including on older versions
- If you need to run some code in response to user interaction, put the code directly in an event handler or use a [function binding](references/bind.md) as appropriate
- If you need to log values for debugging purposes, use [`$inspect`](references/inspect.md)
- If you need to observe something external to Svelte, use [`createSubscriber`](references/svelte-reactivity.md)

Never wrap the contents of an effect in `if (browser) {...}` or similar — effects do not run on the server.

## `$props`

Treat props as though they will change. For example, values that depend on props should usually use `$derived`:

```js
// @errors: 2451
let { type } = $props();

// do this
let color = $derived(type === 'danger' ? 'red' : 'green');

// don't do this — `color` will not update if `type` changes
let color = type === 'danger' ? 'red' : 'green';
```

## `$inspect.trace`

`$inspect.trace` is a debugging tool for reactivity. If something is not updating properly or running more than it should you can add `$inspect.trace(label)` as the first line of an `$effect` or `$derived.by` (or any function they call) to trace their dependencies and discover which one triggered an update.

## Events

Any element attribute starting with `on` is treated as an event listener:

```svelte
<button onclick={() => {...}}>click me</button>

<!-- attribute shorthand also works -->
<button {onclick}>...</button>

<!-- so do spread attributes -->
<button {...props}>...</button>
```

If you need to attach listeners to `window` or `document` you can use `<svelte:window>` and `<svelte:document>`:

```svelte
<svelte:window onkeydown={...} />
<svelte:document onvisibilitychange={...} />
```

Avoid using `onMount` or `$effect` for this.

## Snippets

[Snippets](references/snippet.md) are a way to define reusable chunks of markup that can be instantiated with the [`{@render ...}`](references/render.md) tag, or passed to components as props. They must be declared within the template.

```svelte
{#snippet greeting(name)}
	<p>hello {name}!</p>
{/snippet}

{@render greeting('world')}
```

> [!NOTE] Snippets declared at the top level of a component (i.e. not inside elements or blocks) can be referenced inside `<script>`. A snippet that doesn't reference component state is also available in a `<script module>`, in which case it can be exported for use by other components.

## Each blocks

Prefer to use [keyed each blocks](references/each.md) — this improves performance by allowing Svelte to surgically insert or remove items rather than updating the DOM belonging to existing items.

> [!NOTE] The key _must_ uniquely identify the object. Do not use the index as a key.

Avoid destructuring if you need to mutate the item (with something like `bind:value={item.count}`, for example).

## Using JavaScript variables in CSS

If you have a JS variable that you want to use inside CSS you can set a CSS custom property with the `style:` directive.

```svelte
<div style:--columns={columns}>...</div>
```

You can then reference `var(--columns)` inside the component's `<style>`.

## Styling child components

The CSS in a component's `<style>` is scoped to that component. If a parent component needs to control the child's styles, the preferred way is to use CSS custom properties:

```svelte
<!-- Parent.svelte -->
<Child --color="red" />

<!-- Child.svelte -->
<h1>Hello</h1>

<style>
	h1 {
		color: var(--color);
	}
</style>
```

If this is impossible (for example, the child component comes from a library) you can use `:global` to override styles:

```svelte
<div>
	<Child />
</div>

<style>
	div :global {
		h1 {
			color: red;
		}
	}
</style>
```

## Context

Consider using context instead of declaring state in a shared module. This will scope the state to the part of the app that needs it, and eliminate the possibility of it leaking between users when server-side rendering.

On 5.40+, consider `createContext` for a type-safe context contract. On earlier
versions, use typed `getContext` / `setContext` with the same shared key. Existing
keyed contexts remain valid on newer versions; do not migrate them unnecessarily.

## Async Svelte

On 5.36+ with the project's existing `experimental.async` enabled, component
[await expressions](references/await-expressions.md) are available. Preserve
existing async configuration and supported `{#await}`/event/load patterns.
`hydratable` is a separate low-level serialization API, not a prerequisite for
await; consult [its reference](references/hydratable.md) only when needed and
verify its availability in the installed version. Never serialize secrets or
server-only data into client HTML.

## New Runes-Mode Work

Prefer runes for new Svelte 5 components where consistent with the project.
Existing legacy components remain supported; do not mix incompatible modes
within a component or perform unsolicited migration. For runes-mode code:

- use `$state` instead of implicit reactivity (e.g. `let count = 0; count += 1`)
- use `$derived` and `$effect` instead of `$:` assignments and statements (but only use effects when there is no better solution)
- use `$props` instead of `export let`, `$$props` and `$$restProps`
- use `onclick={...}` instead of `on:click={...}`
- use `{#snippet ...}` and `{@render ...}` instead of `<slot>` and `$$slots` and `<svelte:fragment>`
- use `<DynamicComponent>` instead of `<svelte:component this={DynamicComponent}>`
- use `import Self from './ThisComponent.svelte'` and `<Self>` instead of `<svelte:self>`
- use `$state` objects/classes for appropriate new shared reactive logic in `.svelte.js`/`.svelte.ts`; [stores](https://svelte.dev/docs/svelte/stores) remain valid for existing contracts, streams, and manual subscription control. Scope user state per request/component tree for SSR
- consider `{@attach ...}` on 5.29+ when its lifecycle/composition fits; [actions](https://svelte.dev/docs/svelte/use) remain supported and must not be converted solely for style
- use arrays/objects in `class` on 5.16+ where useful; string classes and `class:` remain valid, especially on earlier versions
