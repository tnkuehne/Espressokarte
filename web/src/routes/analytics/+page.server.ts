import type { PageServerLoad } from "./$types";
import { fetchAllCafesServer, fetchAllPriceRecordsServer } from "$lib/cloudkit.server";
import {
	computeAnalytics,
	serializeAnalytics,
	deserializeAnalytics,
	type AnalyticsData,
} from "$lib/analytics";

const CACHE_KEY = "analytics-data";
const CACHE_TTL_SECONDS = 60 * 60; // 1 hour

export const load: PageServerLoad = async ({ platform }) => {
	// Try to get cached data
	if (platform?.env?.ANALYTICS_CACHE) {
		try {
			const cached = await platform.env.ANALYTICS_CACHE.get(CACHE_KEY);
			if (cached) {
				const data = deserializeAnalytics(cached);
				// Check if cache is still fresh (within TTL)
				const cacheAge =
					(Date.now() - new Date(data.generatedAt).getTime()) / 1000;
				if (cacheAge < CACHE_TTL_SECONDS) {
					return {
						analytics: data,
						fromCache: true,
					};
				}
			}
		} catch (e) {
			console.error("Failed to read from cache:", e);
		}
	}

	// Fetch fresh data from CloudKit
	try {
		const [cafes, priceRecords] = await Promise.all([
			fetchAllCafesServer(),
			fetchAllPriceRecordsServer(),
		]);

		const analytics = computeAnalytics(cafes, priceRecords);

		// Cache the result
		if (platform?.env?.ANALYTICS_CACHE) {
			try {
				await platform.env.ANALYTICS_CACHE.put(
					CACHE_KEY,
					serializeAnalytics(analytics),
					{ expirationTtl: CACHE_TTL_SECONDS }
				);
			} catch (e) {
				console.error("Failed to write to cache:", e);
			}
		}

		return {
			analytics,
			fromCache: false,
		};
	} catch (e) {
		console.error("Failed to fetch analytics data:", e);

		// Return empty analytics on error
		const emptyAnalytics: AnalyticsData = {
			totalCafes: 0,
			totalPriceEntries: 0,
			uniqueContributors: 0,
			averageEspressoPrice: null,
			priceDistribution: [],
			drinkAverages: [],
			monthlyActivity: [],
			generatedAt: new Date().toISOString(),
		};

		return {
			analytics: emptyAnalytics,
			fromCache: false,
			error: "Failed to load analytics data",
		};
	}
};
