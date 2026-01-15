<script lang="ts">
    import "../app.css";
    import { ModeWatcher } from "mode-watcher";

    import Coffee from "@lucide/svelte/icons/coffee";
    import ChartBar from "@lucide/svelte/icons/chart-bar";

    let { children } = $props();
</script>

<ModeWatcher />

<svelte:head>
    <link rel="icon" href="/favicon.png" />
</svelte:head>

<div class="min-h-screen flex flex-col">
    <header class="border-b border-border bg-card px-4 py-3 sticky top-0 z-50">
        <div class="max-w-7xl mx-auto flex items-center justify-between">
            <div class="flex items-center gap-2">
                <Coffee class="h-6 w-6 text-espresso-expensive" />
                <a
                    href="/"
                    class="text-xl font-bold text-foreground hover:text-primary transition-colors"
                >
                    Espressokarte
                </a>
            </div>
            <nav>
                <a
                    href="/analytics"
                    class="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                    <ChartBar class="h-4 w-4" />
                    <span>Analytics</span>
                </a>
            </nav>
        </div>
    </header>

    <main class="flex-1">
        {@render children()}
    </main>

    <footer class="border-t border-border bg-card px-4 py-4">
        <div
            class="max-w-7xl mx-auto text-center text-sm text-muted-foreground"
        >
            <p>
                Find espresso prices near you. Data contributed by the
                community.
            </p>
            <p class="mt-1">
                <a
                    href="https://apps.apple.com"
                    class="text-primary hover:underline"
                >
                    Download the iOS app
                </a>
                to contribute prices.
            </p>
        </div>
    </footer>
</div>
