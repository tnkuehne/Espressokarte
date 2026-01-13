<script lang="ts">
	import { onMount } from 'svelte';
	import { PUBLIC_MAPKIT_TOKEN, PUBLIC_CLOUDKIT_TOKEN } from '$env/static/public';
	import { initCloudKit, fetchAllCafes, fetchPriceHistory, fetchAllPriceRecords } from '$lib/cloudkit';
	import { initMapKit, createMap, addCafesToMap } from '$lib/mapkit';
	import type { Cafe, PriceRecord } from '$lib/types';
	import { formatPrice, getPriceCategory, findDrinkPrice } from '$lib/types';
	import type { Attachment } from 'svelte/attachments';
	import Loader2 from '@lucide/svelte/icons/loader-2';
	import MapPin from '@lucide/svelte/icons/map-pin';
	import History from '@lucide/svelte/icons/history';
	import ChevronsUpDown from '@lucide/svelte/icons/chevrons-up-down';
	import Coffee from '@lucide/svelte/icons/coffee';
	import * as Sheet from '$lib/components/ui/sheet';
	import * as Select from '$lib/components/ui/select';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import PriceHistoryItem from '$lib/components/PriceHistoryItem.svelte';

	let cafes = $state<Cafe[]>([]);
	let allPriceRecords = $state<PriceRecord[]>([]);
	let mapReady = $state(false);
	let cafesLoading = $state(true);
	let error = $state<string | null>(null);
	let map = $state<mapkit.Map | null>(null);

	// Drink filter
	let selectedDrink = $state('Espresso');
	let availableDrinks = $derived(() => {
		const drinkSet = new Set<string>();
		for (const record of allPriceRecords) {
			for (const drink of record.drinks) {
				drinkSet.add(drink.name);
			}
		}
		const sorted = Array.from(drinkSet).sort();
		// Keep Espresso first
		const espressoIndex = sorted.indexOf('Espresso');
		if (espressoIndex > 0) {
			sorted.splice(espressoIndex, 1);
			sorted.unshift('Espresso');
		}
		return sorted.length > 0 ? sorted : ['Espresso'];
	});

	// Build a map of cafe ID -> price for selected drink
	let cafePrices = $derived(() => {
		const priceMap = new Map<string, number | null>();
		
		// Group records by cafe, get latest for each
		const latestByCafe = new Map<string, PriceRecord>();
		for (const record of allPriceRecords) {
			const existing = latestByCafe.get(record.cafeRecordName);
			if (!existing || record.date > existing.date) {
				latestByCafe.set(record.cafeRecordName, record);
			}
		}
		
		for (const cafe of cafes) {
			const latestRecord = latestByCafe.get(cafe.recordName);
			if (latestRecord) {
				const drink = latestRecord.drinks.find(
					d => d.name.toLowerCase() === selectedDrink.toLowerCase() ||
					     d.name.toLowerCase().includes(selectedDrink.toLowerCase())
				);
				priceMap.set(cafe.id, drink?.price ?? null);
			} else {
				priceMap.set(cafe.id, null);
			}
		}
		return priceMap;
	});

	// Sheet state
	let sheetOpen = $state(false);
	let selectedCafe = $state<Cafe | null>(null);
	let priceHistory = $state<PriceRecord[]>([]);
	let loadingHistory = $state(false);

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

	// Track if initial zoom has happened
	let hasInitialZoom = $state(false);

	// Reactively add cafes to map when both are ready
	$effect(() => {
		if (map && cafes.length > 0) {
			const prices = cafePrices();
			
			// Clear and re-add annotations
			map.removeAnnotations(map.annotations);
			const annotations = cafes.map((cafe) => {
				const price = prices.get(cafe.id) ?? cafe.currentPrice;
				return createCafeAnnotation(cafe, handleCafeClick, price);
			});
			map.addAnnotations(annotations);
			
			// Only zoom on initial load
			if (!hasInitialZoom && annotations.length > 0) {
				map.showItems(annotations, {
					animate: true,
					padding: new window.mapkit.Padding(50, 50, 50, 50),
				});
				hasInitialZoom = true;
			}
		}
	});

	// Import createCafeAnnotation for the effect
	import { createCafeAnnotation } from '$lib/mapkit';

	onMount(async () => {
		try {
			// Start both initializations in parallel
			const cafesPromise = initCloudKit(PUBLIC_CLOUDKIT_TOKEN).then(() => 
				Promise.all([fetchAllCafes(), fetchAllPriceRecords()])
			);
			const mapPromise = initMapKit(PUBLIC_MAPKIT_TOKEN).then(() => {
				mapReady = true;
			});

			// Wait for cafes and price records
			const [fetchedCafes, fetchedRecords] = await cafesPromise;
			cafes = fetchedCafes;
			allPriceRecords = fetchedRecords;
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

			<!-- Drink filter - bottom left -->
			<div class="absolute bottom-4 left-4">
				<Select.Root type="single" bind:value={selectedDrink}>
					<Select.Trigger class="w-[160px] bg-background/90 backdrop-blur-sm shadow-md">
						<Coffee class="h-4 w-4 mr-2 shrink-0" />
						<span class="truncate">{selectedDrink}</span>
					</Select.Trigger>
					<Select.Content>
						{#each availableDrinks() as drink}
							<Select.Item value={drink}>{drink}</Select.Item>
						{/each}
					</Select.Content>
				</Select.Root>
			</div>

			<!-- Overlay for loading cafes -->
			{#if cafesLoading}
				<div class="absolute bottom-4 right-4 bg-background/90 backdrop-blur-sm rounded-lg px-4 py-2 shadow-md flex items-center gap-2">
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
			{@const filteredHistory = priceHistory.filter(r => findDrinkPrice(r.drinks, selectedDrink) !== null)}
			{@const sheetPrice = filteredHistory[0] ? findDrinkPrice(filteredHistory[0].drinks, selectedDrink) : null}
			{@const sheetPriceCategory = getPriceCategory(sheetPrice)}
			<!-- Header with gradient background -->
			<div class="bg-gradient-to-br from-primary/10 to-primary/5 px-6 pt-12 pb-6">
				<Badge variant={sheetPriceCategory} class="text-2xl font-bold px-5 py-2.5 mb-2">
					{formatPrice(sheetPrice)}
				</Badge>
				<p class="text-sm text-muted-foreground mb-4">{selectedDrink}</p>
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
						{selectedDrink} Price History
					</h3>

					{#if loadingHistory}
						<div class="flex items-center justify-center py-12">
							<Loader2 class="h-5 w-5 animate-spin text-muted-foreground" />
						</div>
					{:else if filteredHistory.length === 0}
						<div class="text-center py-8 bg-muted/30 rounded-lg">
							<p class="text-muted-foreground text-sm">No {selectedDrink.toLowerCase()} prices recorded</p>
						</div>
					{:else}
						<div class="space-y-3">
							{#each filteredHistory as record (record.id)}
								<PriceHistoryItem {record} drinkName={selectedDrink} />
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
