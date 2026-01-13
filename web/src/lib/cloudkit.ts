import type { Cafe, PriceRecord, DrinkPrice } from "./types";
import { dev } from "$app/environment";

const CONTAINER_IDENTIFIER = "iCloud.com.timokuehne.Espressokarte";

let cloudKitConfigured = false;
let configurePromise: Promise<void> | null = null;

export async function initCloudKit(apiToken: string): Promise<void> {
  if (cloudKitConfigured) return;

  if (configurePromise) {
    return configurePromise;
  }

  configurePromise = new Promise((resolve, reject) => {
    if (typeof window === "undefined") {
      reject(new Error("CloudKit can only be initialized in the browser"));
      return;
    }

    const checkCloudKit = () => {
      if (window.CloudKit) {
        try {
          window.CloudKit.configure({
            containers: [
              {
                containerIdentifier: CONTAINER_IDENTIFIER,
                apiTokenAuth: {
                  apiToken: apiToken,
                  persist: false,
                },
                environment: dev ? "development" : "production",
              },
            ],
          });
          cloudKitConfigured = true;
          resolve();
        } catch (error) {
          reject(error);
        }
      } else {
        setTimeout(checkCloudKit, 100);
      }
    };
    checkCloudKit();
  });

  return configurePromise;
}

export async function fetchAllCafes(): Promise<Cafe[]> {
  if (!cloudKitConfigured) {
    throw new Error("CloudKit not initialized");
  }

  const container = window.CloudKit.getDefaultContainer();
  const database = container.publicCloudDatabase;

  const response = await database.performQuery({
    recordType: "Cafe",
  });

  return response.records.map((record) => ({
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

export async function fetchCafe(recordName: string): Promise<Cafe | null> {
  if (!cloudKitConfigured) {
    throw new Error("CloudKit not initialized");
  }

  const container = window.CloudKit.getDefaultContainer();
  const database = container.publicCloudDatabase;

  try {
    const response = await database.fetchRecords([recordName]);
    if (response.records.length === 0) return null;

    const record = response.records[0];
    return {
      id: record.recordName,
      recordName: record.recordName,
      cafeId: (record.fields.cafeId?.value as string) || "",
      name: (record.fields.name?.value as string) || "Unknown Cafe",
      address: (record.fields.address?.value as string) || "",
      latitude: (record.fields.latitude?.value as number) || 0,
      longitude: (record.fields.longitude?.value as number) || 0,
      currentPrice: (record.fields.currentPrice?.value as number) ?? null,
    };
  } catch {
    return null;
  }
}

export async function fetchPriceHistory(
  cafeRecordName: string,
): Promise<PriceRecord[]> {
  if (!cloudKitConfigured) {
    throw new Error("CloudKit not initialized");
  }

  const container = window.CloudKit.getDefaultContainer();
  const database = container.publicCloudDatabase;

  const response = await database.performQuery({
    recordType: "PriceRecord",
    filterBy: [
      {
        fieldName: "cafeReference",
        comparator: "EQUALS",
        fieldValue: { value: { recordName: cafeRecordName } },
      },
    ],
    sortBy: [{ fieldName: "date", ascending: false }],
  });

  return response.records.map((record) => {
    const asset = record.fields.menuImage?.value as CloudKit.Asset | undefined;

    // Parse drinks from JSON, with backward compatibility for legacy price field
    let drinks: DrinkPrice[] = [];
    const drinksJSON = record.fields.drinksJSON?.value as string | undefined;
    if (drinksJSON) {
      try {
        drinks = JSON.parse(drinksJSON) as DrinkPrice[];
      } catch {
        drinks = [];
      }
    } else {
      // Legacy record: convert price field to drinks array
      const legacyPrice = record.fields.price?.value as number | undefined;
      if (legacyPrice !== undefined) {
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
        (record.fields.cafeReference?.value as CloudKit.Reference)
          ?.recordName || "",
    };
  });
}
