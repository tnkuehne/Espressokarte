export interface Cafe {
	id: string;
	recordName: string;
	cafeId: string;
	name: string;
	address: string;
	latitude: number;
	longitude: number;
	currentPrice: number | null;
}

export interface DrinkPrice {
	name: string;
	price: number;
}

export interface PriceRecord {
	id: string;
	recordName: string;
	drinks: DrinkPrice[];
	date: Date;
	addedBy: string;
	addedByName: string;
	note: string | null;
	menuImageUrl: string | null;
	cafeRecordName: string;
}

export function findEspressoPrice(drinks: DrinkPrice[]): number | null {
	const exact = drinks.find((d) => d.name.toLowerCase() === 'espresso');
	if (exact) return exact.price;

	const partial = drinks.find((d) => {
		const name = d.name.toLowerCase();
		return name.includes('espresso') && !name.includes('double') && !name.includes('doppio');
	});
	return partial?.price ?? null;
}

export function findDrinkPrice(drinks: DrinkPrice[], drinkName: string): number | null {
	const exact = drinks.find((d) => d.name.toLowerCase() === drinkName.toLowerCase());
	if (exact) return exact.price;

	const partial = drinks.find((d) => d.name.toLowerCase().includes(drinkName.toLowerCase()));
	return partial?.price ?? null;
}

export type PriceCategory = 'cheap' | 'medium' | 'expensive' | 'very-expensive' | 'no-price';

/** Price range statistics for a drink type */
export interface DrinkPriceStats {
	minPrice: number;
	maxPrice: number;
	q1: number; // 25th percentile
	median: number; // 50th percentile
	q3: number; // 75th percentile
}

/** Calculate quartile statistics for a set of prices */
export function calculatePriceStats(prices: number[]): DrinkPriceStats | null {
	if (prices.length === 0) return null;

	const sorted = [...prices].sort((a, b) => a - b);
	const count = sorted.length;

	const minPrice = sorted[0];
	const maxPrice = sorted[count - 1];

	// Need at least 4 values and some variance for meaningful quartiles
	// If all values are identical or too few, return null to use fallback ranges
	if (count < 4 || minPrice >= maxPrice) return null;

	const q1Index = Math.floor(count / 4);
	const medianIndex = Math.floor(count / 2);
	const q3Index = Math.floor((count * 3) / 4);

	const q1 = sorted[q1Index];
	const q3 = sorted[q3Index];

	// If quartiles are all equal, return null to use fallback ranges
	if (q1 >= q3) return null;

	return {
		minPrice,
		maxPrice,
		q1,
		median: sorted[medianIndex],
		q3
	};
}

/** Get price category using dynamic stats */
export function getPriceCategoryWithStats(
	price: number | null,
	stats: DrinkPriceStats | null
): PriceCategory {
	if (price === null || price === undefined) return 'no-price';

	if (stats) {
		if (price < stats.q1) return 'cheap';
		if (price < stats.median) return 'medium';
		if (price < stats.q3) return 'expensive';
		return 'very-expensive';
	}

	// Fallback to hardcoded ranges if no stats available
	if (price < 2.0) return 'cheap';
	if (price < 2.5) return 'medium';
	if (price < 3.0) return 'expensive';
	return 'very-expensive';
}

export function getPriceCategory(price: number | null): PriceCategory {
	if (price === null || price === undefined) return 'no-price';
	if (price < 2.0) return 'cheap';
	if (price < 2.5) return 'medium';
	if (price < 3.0) return 'expensive';
	return 'very-expensive';
}

export function getPriceCategoryColor(category: PriceCategory): string {
	switch (category) {
		case 'cheap':
			return '#22c55e';
		case 'medium':
			return '#3b82f6';
		case 'expensive':
			return '#f97316';
		case 'very-expensive':
			return '#ef4444';
		case 'no-price':
		default:
			return '#6b7280';
	}
}

export function formatPrice(price: number | null): string {
	if (price === null || price === undefined) return '—';
	return `€${price.toFixed(2)}`;
}

export function formatDate(date: Date): string {
	return new Intl.DateTimeFormat('de-DE', {
		day: '2-digit',
		month: '2-digit',
		year: 'numeric',
		hour: '2-digit',
		minute: '2-digit'
	}).format(date);
}
