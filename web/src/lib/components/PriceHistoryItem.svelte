<script lang="ts">
    import type { PriceRecord } from "$lib/types";
    import { formatPrice, formatDate, getPriceCategory, findDrinkPrice } from "$lib/types";
    import { Badge } from "./ui/badge";

    let { record, drinkName = "Espresso" }: { record: PriceRecord; drinkName?: string } = $props();

    let drinkPrice = $derived(findDrinkPrice(record.drinks, drinkName));
    let priceCategory = $derived(getPriceCategory(drinkPrice));
</script>

<div class="bg-muted/40 rounded-lg p-4 hover:bg-muted/60 transition-colors">
    <div class="flex items-start justify-between gap-4">
        <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
                <span class="font-medium text-sm">{record.addedByName}</span>
                <span class="text-muted-foreground text-xs">·</span>
                <span class="text-muted-foreground text-xs"
                    >{formatDate(record.date)}</span
                >
            </div>
            {#if record.note}
                <p class="text-sm text-muted-foreground mt-1.5 line-clamp-2">
                    {record.note}
                </p>
            {/if}
        </div>
        <Badge variant={priceCategory} class="shrink-0">
            {formatPrice(drinkPrice)}
        </Badge>
    </div>
</div>
