<script lang="ts">
	import { onMount } from 'svelte';
	import { PUBLIC_MAPKIT_TOKEN, PUBLIC_CLOUDKIT_TOKEN } from '$env/static/public';
	import { initCloudKit, fetchAllCafes, fetchPriceHistory } from '$lib/cloudkit';
	import { initMapKit, createMap, addCafesToMap } from '$lib/mapkit';
	import type { Cafe, PriceRecord } from '$lib/types';
	import { formatPrice, getPriceCategory } from '$lib/types';
	import type { Attachment } from 'svelte/attachments';
	import Loader2 from '@lucide/svelte/icons/loader-2';
	import MapPin from '@lucide/svelte/icons/map-pin';
	import History from '@lucide/svelte/icons/history';
	import * as Sheet from '$lib/components/ui/sheet';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import PriceHistoryItem from '$lib/components/PriceHistoryItem.svelte';

	let cafes = $state<Cafe[]>([]);
	let mapReady = $state(false);
	let cafesLoading = $state(true);
	let error = $state<string | null>(null);
	let map = $state<mapkit.Map | null>(null);

	// Sheet state
	let sheetOpen = $state(false);
	let selectedCafe = $state<Cafe | null>(null);
	let priceHistory = $state<PriceRecord[]>([]);
	let loadingHistory = $state(false);

	let priceCategory = $derived(selectedCafe ? getPriceCategory(selectedCafe.currentPrice) : 'no-price');

	async function handleCafeClick(cafe: Cafe) {
		selectedCafe = cafe;
		sheetOpen = true;
		loadingHistory = true;
		priceHistory = [];

		// Load price history
		try {
			priceHistory = await fetchPriceHistory(cafe.recordName);
		} catch (err) {
			console.error('Failed to load price history:', err);
		} finally {
			loadingHistory = false;
		}
	}

	function mapAttachment(): Attachment<HTMLElement> {
		return (container) => {
			const mapInstance = createMap(container);
			map = mapInstance;

			return () => {
				mapInstance.destroy();
				map = null;
			};
		};
	}

	// Reactively add cafes to map when both are ready
	$effect(() => {
		if (map && cafes.length > 0) {
			addCafesToMap(map, cafes, handleCafeClick);
		}
	});

	onMount(async () => {
		try {
			// Start both initializations in parallel
			// CloudKit path: init -> fetch cafes (doesn't need MapKit)
			// MapKit path: init -> show map (doesn't need CloudKit)
			const cafesPromise = initCloudKit(PUBLIC_CLOUDKIT_TOKEN).then(() => fetchAllCafes());
			const mapPromise = initMapKit(PUBLIC_MAPKIT_TOKEN).then(() => {
				mapReady = true;
			});

			// Wait for cafes (map will show as soon as it's ready via mapReady state)
			cafes = await cafesPromise;
			cafesLoading = false;

			// Ensure map is also ready before we finish
			await mapPromise;
		} catch (err) {
			console.error('Failed to initialize:', err);
			error = err instanceof Error ? err.message : 'Failed to load data';
			cafesLoading = false;
		}
	});
</script>

<div class="flex flex-col h-[calc(100vh-8rem)]">
	<!-- Map -->
	<div class="flex-1 relative">
		{#if error}
			<div class="absolute inset-0 flex items-center justify-center bg-background">
				<div class="text-center p-4">
					<p class="text-destructive font-medium">Error loading data</p>
					<p class="text-muted-foreground text-sm mt-1">{error}</p>
				</div>
			</div>
		{:else if !mapReady}
			<div class="absolute inset-0 flex items-center justify-center bg-background">
				<div class="flex flex-col items-center gap-3">
					<Loader2 class="h-8 w-8 animate-spin text-primary" />
					<p class="text-muted-foreground">Loading map...</p>
				</div>
			</div>
		{:else}
			<div {@attach mapAttachment()} class="w-full h-full"></div>

			<!-- Overlay for loading cafes -->
			{#if cafesLoading}
				<div class="absolute bottom-4 left-4 bg-background/90 backdrop-blur-sm rounded-lg px-4 py-2 shadow-md flex items-center gap-2">
					<Loader2 class="h-4 w-4 animate-spin text-primary" />
					<span class="text-sm text-muted-foreground">Loading cafes...</span>
				</div>
			{/if}
		{/if}
	</div>
</div>

<!-- Cafe Detail Sheet -->
<Sheet.Root bind:open={sheetOpen}>
	<Sheet.Content side="right" class="w-full sm:max-w-md overflow-y-auto p-0">
		{#if selectedCafe}
			<!-- Header with gradient background -->
			<div class="bg-gradient-to-br from-primary/10 to-primary/5 px-6 pt-12 pb-6">
				<Badge variant={priceCategory} class="text-2xl font-bold px-5 py-2.5 mb-4">
					{formatPrice(selectedCafe.currentPrice)}
				</Badge>
				<h2 class="text-2xl font-semibold tracking-tight">{selectedCafe.name}</h2>
				<p class="flex items-center gap-1.5 text-muted-foreground mt-2">
					<MapPin class="h-4 w-4 shrink-0" />
					<span>{selectedCafe.address}</span>
				</p>
			</div>

			<!-- Content -->
			<div class="px-6 py-6 space-y-6">
				<!-- Price History -->
				<div>
					<h3 class="flex items-center gap-2 text-sm font-medium text-muted-foreground uppercase tracking-wide mb-4">
						<History class="h-4 w-4" />
						Price History
					</h3>

					{#if loadingHistory}
						<div class="flex items-center justify-center py-12">
							<Loader2 class="h-5 w-5 animate-spin text-muted-foreground" />
						</div>
					{:else if priceHistory.length === 0}
						<div class="text-center py-8 bg-muted/30 rounded-lg">
							<p class="text-muted-foreground text-sm">No price history yet</p>
						</div>
					{:else}
						<div class="space-y-3">
							{#each priceHistory as record (record.id)}
								<PriceHistoryItem {record} />
							{/each}
						</div>
					{/if}
				</div>

				<!-- CTA -->
				<div class="border-t border-border pt-6">
					<p class="text-center text-sm text-muted-foreground mb-3">
						Want to add or update prices?
					</p>
					<Button href="https://apps.apple.com" class="w-full">
						Download the iOS App
					</Button>
				</div>
			</div>
		{/if}
	</Sheet.Content>
</Sheet.Root>
