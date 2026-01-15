import { env } from "$env/dynamic/public";
import { dev } from "$app/environment";

const CONTAINER_IDENTIFIER = "iCloud.com.timokuehne.Espressokarte";
const CLOUDKIT_API_BASE = "https://api.apple-cloudkit.com/database/1";

interface CloudKitRecord {
	recordName: string;
	recordType: string;
	fields: Record<string, { value: unknown; type?: string }>;
	created?: { timestamp: number; userRecordName?: string };
	modified?: { timestamp: number; userRecordName?: string };
}

interface CloudKitQueryResponse {
	records: CloudKitRecord[];
	continuationMarker?: string;
}

interface CloudKitAsset {
	fileChecksum: string;
	size: number;
	downloadURL: string;
}

interface CloudKitReference {
	recordName: string;
	action?: string;
}

async function cloudKitQuery(
	recordType: string,
	sortBy?: { fieldName: string; ascending: boolean }[]
): Promise<CloudKitRecord[]> {
	const apiToken = env.PUBLIC_CLOUDKIT_TOKEN;
	if (!apiToken) {
		throw new Error("CloudKit API token not configured");
	}

	const environment = dev ? "development" : "production";
	const url = `${CLOUDKIT_API_BASE}/${CONTAINER_IDENTIFIER}/${environment}/public/records/query`;

	const body = {
		query: {
			recordType,
			...(sortBy && { sortBy }),
		},
	};

	const response = await fetch(`${url}?ckAPIToken=${apiToken}`, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
		},
		body: JSON.stringify(body),
	});

	if (!response.ok) {
		const errorText = await response.text();
		throw new Error(`CloudKit query failed: ${response.status} ${errorText}`);
	}

	const data = (await response.json()) as CloudKitQueryResponse;
	return data.records || [];
}

export interface ServerCafe {
	id: string;
	recordName: string;
	cafeId: string;
	name: string;
	address: string;
	latitude: number;
	longitude: number;
	currentPrice: number | null;
}

export interface ServerDrinkPrice {
	name: string;
	price: number;
}

export interface ServerPriceRecord {
	id: string;
	recordName: string;
	drinks: ServerDrinkPrice[];
	date: Date;
	addedBy: string;
	addedByName: string;
	note: string | null;
	menuImageUrl: string | null;
	cafeRecordName: string;
}

export async function fetchAllCafesServer(): Promise<ServerCafe[]> {
	const records = await cloudKitQuery("Cafe");

	return records.map((record) => ({
		id: record.recordName,
		recordName: record.recordName,
		cafeId: (record.fields.cafeId?.value as string) || "",
		name: (record.fields.name?.value as string) || "Unknown Cafe",
		address: (record.fields.address?.value as string) || "",
		latitude: (record.fields.latitude?.value as number) || 0,
		longitude: (record.fields.longitude?.value as number) || 0,
		currentPrice: (record.fields.currentPrice?.value as number) ?? null,
	}));
}

export async function fetchAllPriceRecordsServer(): Promise<ServerPriceRecord[]> {
	const records = await cloudKitQuery("PriceRecord", [
		{ fieldName: "date", ascending: false },
	]);

	return records.map((record) => {
		const asset = record.fields.menuImage?.value as CloudKitAsset | undefined;
		const drinksJSON = record.fields.drinksJSON?.value as string | undefined;
		let drinks: ServerDrinkPrice[] = [];

		if (drinksJSON) {
			try {
				drinks = JSON.parse(drinksJSON);
			} catch {
				// Fallback to legacy price field
			}
		}

		if (drinks.length === 0) {
			const legacyPrice = record.fields.price?.value as number | undefined;
			if (legacyPrice) {
				drinks = [{ name: "Espresso", price: legacyPrice }];
			}
		}

		return {
			id: record.recordName,
			recordName: record.recordName,
			drinks,
			date: new Date((record.fields.date?.value as number) || Date.now()),
			addedBy: (record.fields.addedBy?.value as string) || "",
			addedByName: (record.fields.addedByName?.value as string) || "Anonymous",
			note: (record.fields.note?.value as string) || null,
			menuImageUrl: asset?.downloadURL || null,
			cafeRecordName:
				(record.fields.cafeReference?.value as CloudKitReference)?.recordName || "",
		};
	});
}
