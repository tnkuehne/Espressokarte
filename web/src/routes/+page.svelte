<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { initCloudKit, fetchAllCafes } from '$lib/cloudkit';
	import { initMapKit, createMap, addCafesToMap } from '$lib/mapkit';
	import type { Cafe } from '$lib/types';
	import { Badge } from '$lib/components/ui/badge';
	import { Loader2 } from 'lucide-svelte';

	let { data } = $props();

	let cafes = $state<Cafe[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let mapContainer = $state<HTMLElement | null>(null);
	let map = $state<mapkit.Map | null>(null);

	function handleCafeClick(cafe: Cafe) {
		goto(`/cafe/${cafe.recordName}`);
	}

	onMount(async () => {
		try {
			await Promise.all([
				initMapKit(data.mapkitToken),
				initCloudKit(data.cloudkitToken)
			]);

			cafes = await fetchAllCafes();

			if (mapContainer) {
				map = createMap(mapContainer);
				addCafesToMap(map, cafes, handleCafeClick);
			}

			loading = false;
		} catch (err) {
			console.error('Failed to initialize:', err);
			error = err instanceof Error ? err.message : 'Failed to load data';
			loading = false;
		}
	});
</script>

<div class="flex flex-col h-[calc(100vh-8rem)]">
	<!-- Price Legend -->
	<div class="px-4 py-2 border-b border-border bg-muted/30">
		<div class="max-w-7xl mx-auto flex flex-wrap gap-2 items-center text-sm">
			<span class="text-muted-foreground mr-2">Prices:</span>
			<Badge variant="cheap">{'< €2.00'}</Badge>
			<Badge variant="medium">€2.00-2.50</Badge>
			<Badge variant="expensive">€2.50-3.00</Badge>
			<Badge variant="very-expensive">{'> €3.00'}</Badge>
		</div>
	</div>

	<!-- Map -->
	<div class="flex-1 relative">
		{#if loading}
			<div class="absolute inset-0 flex items-center justify-center bg-background">
				<div class="flex flex-col items-center gap-3">
					<Loader2 class="h-8 w-8 animate-spin text-primary" />
					<p class="text-muted-foreground">Loading cafes...</p>
				</div>
			</div>
		{:else if error}
			<div class="absolute inset-0 flex items-center justify-center bg-background">
				<div class="text-center p-4">
					<p class="text-destructive font-medium">Error loading data</p>
					<p class="text-muted-foreground text-sm mt-1">{error}</p>
				</div>
			</div>
		{:else}
			<div bind:this={mapContainer} class="w-full h-full"></div>
		{/if}
	</div>
</div>
