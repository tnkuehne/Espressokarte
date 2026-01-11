<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { initCloudKit, fetchAllCafes } from '$lib/cloudkit';
	import { initMapKit, createMap, addCafesToMap } from '$lib/mapkit';
	import type { Cafe } from '$lib/types';
	import { formatPrice, getPriceCategory } from '$lib/types';
	import CafeCard from '$lib/components/CafeCard.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import { Loader2, List, Map as MapIcon, Search } from 'lucide-svelte';

	let { data } = $props();

	let cafes = $state<Cafe[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let mapContainer = $state<HTMLElement | null>(null);
	let map = $state<mapkit.Map | null>(null);
	let showList = $state(false);
	let searchQuery = $state('');

	let filteredCafes = $derived(
		searchQuery
			? cafes.filter(
					(cafe) =>
						cafe.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
						cafe.address.toLowerCase().includes(searchQuery.toLowerCase())
				)
			: cafes
	);

	let sortedCafes = $derived(
		[...filteredCafes].sort((a, b) => {
			// Sort by price (ascending), nulls last
			if (a.currentPrice === null && b.currentPrice === null) return 0;
			if (a.currentPrice === null) return 1;
			if (b.currentPrice === null) return -1;
			return a.currentPrice - b.currentPrice;
		})
	);

	function handleCafeClick(cafe: Cafe) {
		goto(`/cafe/${cafe.recordName}`);
	}

	onMount(async () => {
		try {
			// Initialize MapKit and CloudKit
			await Promise.all([
				initMapKit(data.mapkitToken),
				initCloudKit(data.cloudkitToken)
			]);

			// Fetch cafes
			cafes = await fetchAllCafes();

			// Initialize map
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

	$effect(() => {
		if (map && filteredCafes.length > 0) {
			addCafesToMap(map, filteredCafes, handleCafeClick);
		}
	});
</script>

<div class="flex flex-col h-[calc(100vh-8rem)]">
	<!-- Search and Controls -->
	<div class="p-4 border-b border-border bg-background">
		<div class="max-w-7xl mx-auto flex flex-col sm:flex-row gap-3">
			<div class="relative flex-1">
				<Search class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
				<input
					type="text"
					placeholder="Search cafes..."
					bind:value={searchQuery}
					class="w-full pl-10 pr-4 py-2 rounded-lg border border-input bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring"
				/>
			</div>
			<div class="flex gap-2">
				<Button
					variant={showList ? 'outline' : 'default'}
					size="sm"
					onclick={() => (showList = false)}
				>
					<MapIcon class="h-4 w-4 mr-1" />
					Map
				</Button>
				<Button
					variant={showList ? 'default' : 'outline'}
					size="sm"
					onclick={() => (showList = true)}
				>
					<List class="h-4 w-4 mr-1" />
					List
				</Button>
			</div>
		</div>
	</div>

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

	<!-- Content -->
	<div class="flex-1 relative overflow-hidden">
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
			<!-- Map View -->
			<div
				class="absolute inset-0 transition-opacity"
				class:opacity-0={showList}
				class:pointer-events-none={showList}
			>
				<div bind:this={mapContainer} class="w-full h-full"></div>
			</div>

			<!-- List View -->
			<div
				class="absolute inset-0 overflow-y-auto transition-opacity bg-background"
				class:opacity-0={!showList}
				class:pointer-events-none={!showList}
			>
				<div class="max-w-3xl mx-auto p-4 space-y-3">
					{#if sortedCafes.length === 0}
						<div class="text-center py-8">
							<p class="text-muted-foreground">No cafes found</p>
						</div>
					{:else}
						<p class="text-sm text-muted-foreground mb-4">
							{sortedCafes.length} cafe{sortedCafes.length === 1 ? '' : 's'} found
						</p>
						{#each sortedCafes as cafe (cafe.id)}
							<CafeCard {cafe} onclick={() => handleCafeClick(cafe)} />
						{/each}
					{/if}
				</div>
			</div>
		{/if}
	</div>
</div>
