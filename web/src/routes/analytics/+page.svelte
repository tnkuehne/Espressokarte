<script lang="ts">
	import type { PageData } from "./$types";
	import * as Card from "$lib/components/ui/card/index.js";
	import * as Chart from "$lib/components/ui/chart/index.js";
	import { BarChart, AreaChart } from "layerchart";
	import { scaleBand, scaleTime } from "d3-scale";

	let { data }: { data: PageData } = $props();

	const analytics = $derived(data.analytics);

	// Chart configs
	const priceDistributionConfig = {
		count: {
			label: "Cafes",
			color: "var(--chart-1)",
		},
	} satisfies Chart.ChartConfig;

	const drinkAverageConfig = {
		averagePrice: {
			label: "Avg Price",
			color: "var(--chart-2)",
		},
	} satisfies Chart.ChartConfig;

	const activityConfig = {
		entries: {
			label: "Price Entries",
			color: "var(--chart-3)",
		},
	} satisfies Chart.ChartConfig;

	// Format price for display
	function formatPrice(price: number | null): string {
		if (price === null) return "—";
		return `€${price.toFixed(2)}`;
	}

	// Transform monthly activity data for chart
	const activityChartData = $derived(
		analytics.monthlyActivity.map((m) => ({
			date: new Date(m.date),
			entries: m.entries,
		}))
	);
</script>

<svelte:head>
	<title>Analytics | Espressokarte</title>
</svelte:head>

<div class="container mx-auto max-w-6xl px-4 py-8">
	<div class="mb-8">
		<h1 class="text-3xl font-bold">Analytics</h1>
		<p class="text-muted-foreground mt-1">
			Insights from coffee prices across cafes
		</p>
	</div>

	<!-- Summary Stats -->
	<div class="mb-8 grid grid-cols-2 gap-4 md:grid-cols-4">
		<Card.Root>
			<Card.Header class="pb-2">
				<Card.Description>Total Cafes</Card.Description>
			</Card.Header>
			<Card.Content>
				<p class="text-3xl font-bold">{analytics.totalCafes}</p>
			</Card.Content>
		</Card.Root>

		<Card.Root>
			<Card.Header class="pb-2">
				<Card.Description>Price Entries</Card.Description>
			</Card.Header>
			<Card.Content>
				<p class="text-3xl font-bold">{analytics.totalPriceEntries}</p>
			</Card.Content>
		</Card.Root>

		<Card.Root>
			<Card.Header class="pb-2">
				<Card.Description>Contributors</Card.Description>
			</Card.Header>
			<Card.Content>
				<p class="text-3xl font-bold">{analytics.uniqueContributors}</p>
			</Card.Content>
		</Card.Root>

		<Card.Root>
			<Card.Header class="pb-2">
				<Card.Description>Avg. Espresso</Card.Description>
			</Card.Header>
			<Card.Content>
				<p class="text-3xl font-bold">
					{formatPrice(analytics.averageEspressoPrice)}
				</p>
			</Card.Content>
		</Card.Root>
	</div>

	<!-- Charts Grid -->
	<div class="grid gap-6 md:grid-cols-2">
		<!-- Price Distribution -->
		{#if analytics.priceDistribution.length > 0}
			<Card.Root>
				<Card.Header>
					<Card.Title>Espresso Price Distribution</Card.Title>
					<Card.Description>
						Number of cafes by price range
					</Card.Description>
				</Card.Header>
				<Card.Content>
					<Chart.Container
						config={priceDistributionConfig}
						class="aspect-[4/3] w-full"
					>
						<BarChart
							data={analytics.priceDistribution}
							x="range"
							xScale={scaleBand().padding(0.2)}
							series={[
								{
									key: "count",
									label: priceDistributionConfig.count.label,
									color: priceDistributionConfig.count.color,
								},
							]}
							axis="x"
							props={{
								xAxis: {
									format: (d: string) => d,
								},
							}}
						>
							{#snippet tooltip()}
								<Chart.Tooltip />
							{/snippet}
						</BarChart>
					</Chart.Container>
				</Card.Content>
			</Card.Root>
		{/if}

		<!-- Drink Averages -->
		{#if analytics.drinkAverages.length > 0}
			<Card.Root>
				<Card.Header>
					<Card.Title>Average Price by Drink</Card.Title>
					<Card.Description>
						Most common drinks and their average prices
					</Card.Description>
				</Card.Header>
				<Card.Content>
					<Chart.Container
						config={drinkAverageConfig}
						class="aspect-[4/3] w-full"
					>
						<BarChart
							data={analytics.drinkAverages}
							x="drink"
							xScale={scaleBand().padding(0.2)}
							series={[
								{
									key: "averagePrice",
									label: drinkAverageConfig.averagePrice.label,
									color: drinkAverageConfig.averagePrice.color,
								},
							]}
							axis="x"
							props={{
								xAxis: {
									format: (d: string) =>
										d.length > 10 ? d.slice(0, 10) + "..." : d,
								},
							}}
						>
							{#snippet tooltip()}
								<Chart.Tooltip
									labelFormatter={(value) => `${value}`}
								/>
							{/snippet}
						</BarChart>
					</Chart.Container>
				</Card.Content>
			</Card.Root>
		{/if}

		<!-- Activity Timeline -->
		{#if activityChartData.length > 1}
			<Card.Root class="md:col-span-2">
				<Card.Header>
					<Card.Title>Contribution Activity</Card.Title>
					<Card.Description>
						Price entries added over time
					</Card.Description>
				</Card.Header>
				<Card.Content>
					<Chart.Container
						config={activityConfig}
						class="aspect-[21/9] w-full"
					>
						<AreaChart
							data={activityChartData}
							x="date"
							xScale={scaleTime()}
							series={[
								{
									key: "entries",
									label: activityConfig.entries.label,
									color: activityConfig.entries.color,
								},
							]}
							axis="x"
							props={{
								xAxis: {
									format: (d: Date) =>
										new Intl.DateTimeFormat("de-DE", {
											month: "short",
											year: "2-digit",
										}).format(d),
								},
							}}
						>
							{#snippet tooltip()}
								<Chart.Tooltip
									labelFormatter={(value) => {
										if (value instanceof Date) {
											return new Intl.DateTimeFormat("de-DE", {
												month: "long",
												year: "numeric",
											}).format(value);
										}
										return String(value);
									}}
								/>
							{/snippet}
						</AreaChart>
					</Chart.Container>
				</Card.Content>
			</Card.Root>
		{/if}
	</div>

	<!-- Cache Info (subtle) -->
	<p class="text-muted-foreground mt-8 text-center text-xs">
		{#if data.fromCache}
			Data cached at {new Date(analytics.generatedAt).toLocaleString("de-DE")}
		{:else}
			Data generated at {new Date(analytics.generatedAt).toLocaleString("de-DE")}
		{/if}
	</p>
</div>
