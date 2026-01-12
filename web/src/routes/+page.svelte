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
	import * as Card from '$lib/components/ui/card';
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
			await initMapKit(PUBLIC_MAPKIT_TOKEN);
			mapReady = true;

			await initCloudKit(PUBLIC_CLOUDKIT_TOKEN);
			cafes = await fetchAllCafes();
			cafesLoading = false;
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
	<Sheet.Content side="right" class="w-full sm:max-w-md overflow-y-auto">
		{#if selectedCafe}
			<Sheet.Header>
				<Sheet.Title class="text-xl">{selectedCafe.name}</Sheet.Title>
				<Sheet.Description class="flex items-center gap-1">
					<MapPin class="h-4 w-4" />
					{selectedCafe.address}
				</Sheet.Description>
			</Sheet.Header>

			<div class="space-y-6 py-4">
				<!-- Current Price -->
				<div class="flex items-center justify-between">
					<span class="text-muted-foreground">Current Espresso Price</span>
					<Badge variant={priceCategory} class="text-lg px-4 py-2">
						{formatPrice(selectedCafe.currentPrice)}
					</Badge>
				</div>

				<!-- Price History -->
				<Card.Root>
					<Card.Header class="pb-3">
						<Card.Title class="flex items-center gap-2 text-base">
							<History class="h-4 w-4" />
							Price History
						</Card.Title>
					</Card.Header>
					<Card.Content>
						{#if loadingHistory}
							<div class="flex items-center justify-center py-8">
								<Loader2 class="h-6 w-6 animate-spin text-primary" />
							</div>
						{:else if priceHistory.length === 0}
							<p class="text-center text-muted-foreground py-4 text-sm">
								No price history available yet.
							</p>
						{:else}
							<div class="divide-y divide-border">
								{#each priceHistory as record (record.id)}
									<PriceHistoryItem {record} showImage={true} />
								{/each}
							</div>
						{/if}
					</Card.Content>
				</Card.Root>

				<!-- CTA to download app -->
				<Card.Root class="bg-muted/50">
					<Card.Content class="text-center py-6">
						<p class="text-muted-foreground mb-3 text-sm">
							Want to add or update prices?
						</p>
						<Button href="https://apps.apple.com" variant="default" size="sm">
							Download the iOS App
						</Button>
					</Card.Content>
				</Card.Root>
			</div>
		{/if}
	</Sheet.Content>
</Sheet.Root>
