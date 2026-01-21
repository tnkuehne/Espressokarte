import { dev } from "$app/environment";
import { env } from "$env/dynamic/private";

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

/**
 * Convert PEM private key to CryptoKey for signing
 */
async function importPrivateKey(pemKey: string): Promise<CryptoKey> {
	// Remove PEM headers and decode base64
	const pemContents = pemKey
		.replace(/-----BEGIN EC PRIVATE KEY-----/, "")
		.replace(/-----END EC PRIVATE KEY-----/, "")
		.replace(/-----BEGIN PRIVATE KEY-----/, "")
		.replace(/-----END PRIVATE KEY-----/, "")
		.replace(/\s/g, "");

	const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

	// Try PKCS8 format first, then EC format
	try {
		return await crypto.subtle.importKey(
			"pkcs8",
			binaryDer,
			{ name: "ECDSA", namedCurve: "P-256" },
			false,
			["sign"]
		);
	} catch {
		// If PKCS8 fails, the key might be in SEC1/EC format
		// We need to wrap it in PKCS8 format
		throw new Error(
			"Failed to import private key. Ensure it's in PKCS8 format. " +
				"Convert with: openssl pkcs8 -topk8 -nocrypt -in key.pem -out key-pkcs8.pem"
		);
	}
}

/**
 * Create CloudKit Server-to-Server request signature
 */
async function createSignature(
	privateKey: CryptoKey,
	date: string,
	body: string,
	subpath: string
): Promise<string> {
	// Hash the body with SHA-256
	const bodyBytes = new TextEncoder().encode(body);
	const bodyHashBuffer = await crypto.subtle.digest("SHA-256", bodyBytes);
	const bodyHash = btoa(String.fromCharCode(...new Uint8Array(bodyHashBuffer)));

	// Create the message to sign: date:bodyHash:subpath
	const message = `${date}:${bodyHash}:${subpath}`;
	const messageBytes = new TextEncoder().encode(message);

	// Sign with ECDSA SHA-256
	const signatureBuffer = await crypto.subtle.sign(
		{ name: "ECDSA", hash: "SHA-256" },
		privateKey,
		messageBytes
	);

	// Convert to base64
	return btoa(String.fromCharCode(...new Uint8Array(signatureBuffer)));
}

/**
 * Make authenticated CloudKit API request
 */
async function cloudKitQuery(
	recordType: string,
	sortBy?: { fieldName: string; ascending: boolean }[]
): Promise<CloudKitRecord[]> {
	const keyId = env.CLOUDKIT_KEY_ID;
	const privateKeyPem = env.CLOUDKIT_PRIVATE_KEY;

	if (!keyId || !privateKeyPem) {
		throw new Error(
			"CloudKit Server-to-Server credentials not configured. " +
				"Set CLOUDKIT_KEY_ID and CLOUDKIT_PRIVATE_KEY environment variables."
		);
	}

	const privateKey = await importPrivateKey(privateKeyPem);

	const environment = dev ? "development" : "production";
	const subpath = `/database/1/${CONTAINER_IDENTIFIER}/${environment}/public/records/query`;
	const url = `${CLOUDKIT_API_BASE}/${CONTAINER_IDENTIFIER}/${environment}/public/records/query`;

	const body = JSON.stringify({
		query: {
			recordType,
			...(sortBy && { sortBy }),
		},
	});

	// ISO8601 date with milliseconds
	const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

	const signature = await createSignature(privateKey, date, body, subpath);

	const response = await fetch(url, {
		method: "POST",
		headers: {
			"Content-Type": "text/plain",
			"X-Apple-CloudKit-Request-KeyID": keyId,
			"X-Apple-CloudKit-Request-ISO8601Date": date,
			"X-Apple-CloudKit-Request-SignatureV1": signature,
		},
		body,
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
