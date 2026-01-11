<script lang="ts">
	import type { Cafe } from '$lib/types';
	import { formatPrice, getPriceCategory } from '$lib/types';
	import * as Card from './ui/card';
	import { Badge } from './ui/badge';
	import { MapPin } from 'lucide-svelte';

	let { cafe, onclick }: { cafe: Cafe; onclick?: () => void } = $props();

	let priceCategory = $derived(getPriceCategory(cafe.currentPrice));
</script>

<button
	class="w-full text-left transition-transform hover:scale-[1.02] focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 rounded-xl"
	{onclick}
	type="button"
>
	<Card.Root class="p-4">
		<div class="flex items-start justify-between gap-3">
			<div class="flex-1 min-w-0">
				<h3 class="font-semibold text-foreground truncate">{cafe.name}</h3>
				<div class="flex items-center gap-1 mt-1 text-sm text-muted-foreground">
					<MapPin class="h-3 w-3 flex-shrink-0" />
					<span class="truncate">{cafe.address}</span>
				</div>
			</div>
			<Badge variant={priceCategory} class="flex-shrink-0">
				{formatPrice(cafe.currentPrice)}
			</Badge>
		</div>
	</Card.Root>
</button>
