<script lang="ts">
    import type { PriceRecord } from "$lib/types";
    import { formatPrice, formatDate, getPriceCategory } from "$lib/types";
    import { Badge } from "./ui/badge";

    import User from "@lucide/svelte/icons/user";
    import Calendar from "@lucide/svelte/icons/calendar";
    import MessageSquare from "@lucide/svelte/icons/message-square";
    import Image from "@lucide/svelte/icons/image";

    let {
        record,
        showImage = false,
    }: { record: PriceRecord; showImage?: boolean } = $props();

    let priceCategory = $derived(getPriceCategory(record.price));
</script>

<div class="border-b border-border py-4 last:border-b-0">
    <div class="flex items-start justify-between gap-3">
        <div class="flex-1 min-w-0 space-y-2">
            <div class="flex items-center gap-2 text-sm text-muted-foreground">
                <User class="h-3.5 w-3.5" />
                <span>{record.addedByName}</span>
            </div>
            <div class="flex items-center gap-2 text-sm text-muted-foreground">
                <Calendar class="h-3.5 w-3.5" />
                <span>{formatDate(record.date)}</span>
            </div>
            {#if record.note}
                <div
                    class="flex items-start gap-2 text-sm text-muted-foreground"
                >
                    <MessageSquare class="h-3.5 w-3.5 mt-0.5" />
                    <span>{record.note}</span>
                </div>
            {/if}
        </div>
        <Badge variant={priceCategory} class="text-sm px-3 py-1">
            {formatPrice(record.price)}
        </Badge>
    </div>

    {#if showImage && record.menuImageUrl}
        <div class="mt-3">
            <button
                class="flex items-center gap-2 text-sm text-primary hover:underline"
                onclick={() => window.open(record.menuImageUrl!, "_blank")}
                type="button"
            >
                <Image class="h-4 w-4" />
                View menu photo
            </button>
        </div>
    {/if}
</div>
