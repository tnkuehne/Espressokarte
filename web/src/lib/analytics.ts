import type { ServerCafe, ServerPriceRecord, ServerDrinkPrice } from "./cloudkit.server";

export interface AnalyticsData {
	// Summary stats
	totalCafes: number;
	totalPriceEntries: number;
	uniqueContributors: number;
	averageEspressoPrice: number | null;

	// Price distribution for espresso (buckets)
	priceDistribution: PriceBucket[];

	// Average price by drink type
	drinkAverages: DrinkAverage[];

	// Monthly contribution activity
	monthlyActivity: MonthlyActivity[];

	// Metadata
	generatedAt: string;
}

export interface PriceBucket {
	range: string;
	min: number;
	max: number;
	count: number;
}

export interface DrinkAverage {
	drink: string;
	averagePrice: number;
	count: number;
}

export interface MonthlyActivity {
	month: string;
	date: Date;
	entries: number;
}

function findEspressoPrice(drinks: ServerDrinkPrice[]): number | null {
	const exact = drinks.find((d) => d.name.toLowerCase() === "espresso");
	if (exact) return exact.price;

	const partial = drinks.find((d) => {
		const name = d.name.toLowerCase();
		return name.includes("espresso") && !name.includes("double") && !name.includes("doppio");
	});
	return partial?.price ?? null;
}

export function computeAnalytics(
	cafes: ServerCafe[],
	priceRecords: ServerPriceRecord[]
): AnalyticsData {
	// Summary stats
	const totalCafes = cafes.length;
	const totalPriceEntries = priceRecords.length;

	// Unique contributors
	const contributors = new Set(priceRecords.map((r) => r.addedBy).filter(Boolean));
	const uniqueContributors = contributors.size;

	// Calculate espresso prices for distribution
	const espressoPrices: number[] = [];
	const cafeLatestEspresso = new Map<string, number>();

	for (const record of priceRecords) {
		const espressoPrice = findEspressoPrice(record.drinks);
		if (espressoPrice !== null && record.cafeRecordName) {
			// Only keep the latest price per cafe for distribution
			if (!cafeLatestEspresso.has(record.cafeRecordName)) {
				cafeLatestEspresso.set(record.cafeRecordName, espressoPrice);
			}
		}
	}

	espressoPrices.push(...cafeLatestEspresso.values());

	// Average espresso price
	const averageEspressoPrice =
		espressoPrices.length > 0
			? espressoPrices.reduce((a, b) => a + b, 0) / espressoPrices.length
			: null;

	// Price distribution buckets
	const priceDistribution = computePriceDistribution(espressoPrices);

	// Average price by drink type
	const drinkAverages = computeDrinkAverages(priceRecords);

	// Monthly activity
	const monthlyActivity = computeMonthlyActivity(priceRecords);

	return {
		totalCafes,
		totalPriceEntries,
		uniqueContributors,
		averageEspressoPrice,
		priceDistribution,
		drinkAverages,
		monthlyActivity,
		generatedAt: new Date().toISOString(),
	};
}

function computePriceDistribution(prices: number[]): PriceBucket[] {
	if (prices.length === 0) return [];

	// Create buckets from 1.00 to 5.00+ in 0.50 increments
	const buckets: PriceBucket[] = [
		{ range: "< €1.50", min: 0, max: 1.5, count: 0 },
		{ range: "€1.50 - €2.00", min: 1.5, max: 2.0, count: 0 },
		{ range: "€2.00 - €2.50", min: 2.0, max: 2.5, count: 0 },
		{ range: "€2.50 - €3.00", min: 2.5, max: 3.0, count: 0 },
		{ range: "€3.00 - €3.50", min: 3.0, max: 3.5, count: 0 },
		{ range: "€3.50 - €4.00", min: 3.5, max: 4.0, count: 0 },
		{ range: "> €4.00", min: 4.0, max: Infinity, count: 0 },
	];

	for (const price of prices) {
		for (const bucket of buckets) {
			if (price >= bucket.min && price < bucket.max) {
				bucket.count++;
				break;
			}
		}
	}

	// Only return buckets with data
	return buckets.filter((b) => b.count > 0);
}

function computeDrinkAverages(priceRecords: ServerPriceRecord[]): DrinkAverage[] {
	const drinkPrices = new Map<string, number[]>();

	for (const record of priceRecords) {
		for (const drink of record.drinks) {
			const normalizedName = normalizeDrinkName(drink.name);
			if (!drinkPrices.has(normalizedName)) {
				drinkPrices.set(normalizedName, []);
			}
			drinkPrices.get(normalizedName)!.push(drink.price);
		}
	}

	const averages: DrinkAverage[] = [];
	for (const [drink, prices] of drinkPrices) {
		if (prices.length >= 3) {
			// Only include drinks with at least 3 data points
			averages.push({
				drink,
				averagePrice: prices.reduce((a, b) => a + b, 0) / prices.length,
				count: prices.length,
			});
		}
	}

	// Sort by count (most popular first)
	return averages.sort((a, b) => b.count - a.count).slice(0, 8); // Top 8 drinks
}

function normalizeDrinkName(name: string): string {
	const lower = name.toLowerCase().trim();

	// Normalize common variations
	if (lower === "espresso" || lower.includes("espresso")) {
		if (lower.includes("double") || lower.includes("doppio")) {
			return "Doppio";
		}
		return "Espresso";
	}
	if (lower.includes("cappuccino")) return "Cappuccino";
	if (lower.includes("latte macchiato")) return "Latte Macchiato";
	if (lower.includes("flat white")) return "Flat White";
	if (lower.includes("americano")) return "Americano";
	if (lower.includes("cortado")) return "Cortado";
	if (lower.includes("macchiato") && !lower.includes("latte")) return "Macchiato";
	if (lower.includes("filter") || lower.includes("filterkaffee")) return "Filter Coffee";

	// Capitalize first letter of each word
	return name
		.split(" ")
		.map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
		.join(" ");
}

function computeMonthlyActivity(priceRecords: ServerPriceRecord[]): MonthlyActivity[] {
	const monthCounts = new Map<string, { date: Date; count: number }>();

	for (const record of priceRecords) {
		const date = new Date(record.date);
		const monthKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;

		if (!monthCounts.has(monthKey)) {
			monthCounts.set(monthKey, {
				date: new Date(date.getFullYear(), date.getMonth(), 1),
				count: 0,
			});
		}
		monthCounts.get(monthKey)!.count++;
	}

	// Convert to array and sort by date
	const activity: MonthlyActivity[] = [];
	for (const [monthKey, data] of monthCounts) {
		activity.push({
			month: formatMonth(data.date),
			date: data.date,
			entries: data.count,
		});
	}

	return activity.sort((a, b) => a.date.getTime() - b.date.getTime());
}

function formatMonth(date: Date): string {
	return new Intl.DateTimeFormat("de-DE", { month: "short", year: "2-digit" }).format(date);
}

// Serialization helpers for KV storage
export function serializeAnalytics(data: AnalyticsData): string {
	return JSON.stringify({
		...data,
		monthlyActivity: data.monthlyActivity.map((m) => ({
			...m,
			date: m.date.toISOString(),
		})),
	});
}

export function deserializeAnalytics(json: string): AnalyticsData {
	const data = JSON.parse(json);
	return {
		...data,
		monthlyActivity: data.monthlyActivity.map(
			(m: { month: string; date: string; entries: number }) => ({
				...m,
				date: new Date(m.date),
			})
		),
	};
}
