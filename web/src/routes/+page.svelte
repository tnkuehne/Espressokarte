<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { PUBLIC_MAPKIT_TOKEN, PUBLIC_CLOUDKIT_TOKEN } from '$env/static/public';
	import { initCloudKit, fetchAllCafes } from '$lib/cloudkit';
	import { initMapKit, createMap, addCafesToMap } from '$lib/mapkit';
	import type { Cafe } from '$lib/types';
	import type { Attachment } from 'svelte/attachments';
	import Loader2 from '@lucide/svelte/icons/loader-2';

	let cafes = $state<Cafe[]>([]);
	let mapReady = $state(false);
	let cafesLoading = $state(true);
	let error = $state<string | null>(null);
	let map = $state<mapkit.Map | null>(null);

	function handleCafeClick(cafe: Cafe) {
		goto(`/cafe/${cafe.recordName}`);
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
