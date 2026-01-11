<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { initCloudKit, fetchCafe, fetchPriceHistory } from '$lib/cloudkit';
	import { initMapKit, createMap, focusOnCafe, createCafeAnnotation } from '$lib/mapkit';
	import type { Cafe, PriceRecord } from '$lib/types';
	import { formatPrice, getPriceCategory } from '$lib/types';
	import PriceHistoryItem from '$lib/components/PriceHistoryItem.svelte';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import * as Card from '$lib/components/ui/card';
	import { ArrowLeft, MapPin, Loader2, History } from 'lucide-svelte';

	let { data } = $props();

	let cafe = $state<Cafe | null>(null);
	let priceHistory = $state<PriceRecord[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let mapContainer = $state<HTMLElement | null>(null);
	let map = $state<mapkit.Map | null>(null);

	let priceCategory = $derived(cafe ? getPriceCategory(cafe.currentPrice) : 'no-price');

	onMount(async () => {
		try {
			// Initialize CloudKit and MapKit
			await Promise.all([
				initCloudKit(data.cloudkitToken),
				initMapKit(data.mapkitToken)
			]);

			// Fetch cafe details
			cafe = await fetchCafe(data.cafeId);

			if (!cafe) {
				error = 'Cafe not found';
				loading = false;
				return;
			}

			// Fetch price history
			priceHistory = await fetchPriceHistory(data.cafeId);

			// Initialize map
			if (mapContainer && cafe) {
				map = createMap(mapContainer);
				const annotation = createCafeAnnotation(cafe, () => {});
				map.addAnnotation(annotation);
				focusOnCafe(map, cafe);
			}

			loading = false;
		} catch (err) {
			console.error('Failed to load cafe:', err);
			error = err instanceof Error ? err.message : 'Failed to load cafe';
			loading = false;
		}
	});
</script>

<svelte:head>
	{#if cafe}
		<title>{cafe.name} - Espressokarte</title>
	{:else}
		<title>Cafe - Espressokarte</title>
	{/if}
</svelte:head>

<div class="min-h-screen bg-background">
	<!-- Back button -->
	<div class="sticky top-0 z-10 bg-background border-b border-border px-4 py-3">
		<div class="max-w-3xl mx-auto">
			<Button variant="ghost" size="sm" onclick={() => goto('/')}>
				<ArrowLeft class="h-4 w-4 mr-2" />
				Back to map
			</Button>
		</div>
	</div>

	{#if loading}
		<div class="flex items-center justify-center py-20">
			<div class="flex flex-col items-center gap-3">
				<Loader2 class="h-8 w-8 animate-spin text-primary" />
				<p class="text-muted-foreground">Loading cafe...</p>
			</div>
		</div>
	{:else if error || !cafe}
		<div class="flex items-center justify-center py-20">
			<div class="text-center">
				<p class="text-destructive font-medium">{error || 'Cafe not found'}</p>
				<Button variant="outline" class="mt-4" onclick={() => goto('/')}>
					Return to map
				</Button>
			</div>
		</div>
	{:else}
		<div class="max-w-3xl mx-auto p-4 space-y-6">
			<!-- Cafe Header -->
			<Card.Root>
				<Card.Header>
					<div class="flex items-start justify-between gap-4">
						<div class="flex-1 min-w-0">
							<Card.Title class="text-2xl">{cafe.name}</Card.Title>
							<Card.Description class="flex items-center gap-1 mt-2">
								<MapPin class="h-4 w-4" />
								{cafe.address}
							</Card.Description>
						</div>
						<Badge variant={priceCategory} class="text-lg px-4 py-2">
							{formatPrice(cafe.currentPrice)}
						</Badge>
					</div>
				</Card.Header>
			</Card.Root>

			<!-- Map -->
			<Card.Root class="overflow-hidden">
				<div bind:this={mapContainer} class="w-full h-64"></div>
			</Card.Root>

			<!-- Price History -->
			<Card.Root>
				<Card.Header>
					<Card.Title class="flex items-center gap-2">
						<History class="h-5 w-5" />
						Price History
					</Card.Title>
					<Card.Description>
						{priceHistory.length} price{priceHistory.length === 1 ? '' : 's'} recorded
					</Card.Description>
				</Card.Header>
				<Card.Content>
					{#if priceHistory.length === 0}
						<p class="text-center text-muted-foreground py-4">
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
					<p class="text-muted-foreground mb-3">
						Want to add or update prices?
					</p>
					<Button href="https://apps.apple.com" variant="default">
						Download the iOS App
					</Button>
				</Card.Content>
			</Card.Root>
		</div>
	{/if}
</div>
