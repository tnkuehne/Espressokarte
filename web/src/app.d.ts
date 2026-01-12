// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
	}
}

declare global {
	interface Window {
		mapkit: typeof mapkit;
		CloudKit: typeof CloudKit;
	}

	namespace mapkit {
		class Map {
			constructor(container: string | HTMLElement, options?: MapConstructorOptions);
			showsCompass: number;
			showsScale: number;
			showsMapTypeControl: boolean;
			showsUserLocationControl: boolean;
			showsUserLocation: boolean;
			tracksUserLocation: boolean;
			region: CoordinateRegion;
			annotations: Annotation[];
			addAnnotation(annotation: Annotation): void;
			addAnnotations(annotations: Annotation[]): void;
			removeAnnotation(annotation: Annotation): void;
			removeAnnotations(annotations: Annotation[]): void;
			showItems(items: Annotation[], options?: MapShowItemsOptions): void;
			destroy(): void;
		}

		class Annotation {
			constructor(
				coordinate: Coordinate,
				factory: (coordinate: Coordinate, options: AnnotationConstructorOptions) => Element,
				options?: AnnotationConstructorOptions
			);
			coordinate: Coordinate;
			data: Record<string, unknown>;
			element: Element;
			selected: boolean;
			addEventListener(type: string, listener: (event: AnnotationEvent) => void): void;
		}

		class Coordinate {
			constructor(latitude: number, longitude: number);
			latitude: number;
			longitude: number;
		}

		class CoordinateRegion {
			constructor(center: Coordinate, span: CoordinateSpan);
			center: Coordinate;
			span: CoordinateSpan;
		}

		class CoordinateSpan {
			constructor(latitudeDelta: number, longitudeDelta: number);
			latitudeDelta: number;
			longitudeDelta: number;
		}

		interface MapConstructorOptions {
			center?: Coordinate;
			region?: CoordinateRegion;
			showsCompass?: number;
			showsScale?: number;
			showsMapTypeControl?: boolean;
			showsUserLocationControl?: boolean;
			colorScheme?: number;
		}

		interface AnnotationConstructorOptions {
			title?: string;
			subtitle?: string;
			data?: Record<string, unknown>;
			selected?: boolean;
			animates?: boolean;
			draggable?: boolean;
			enabled?: boolean;
			visible?: boolean;
		}

		interface AnnotationEvent {
			annotation: Annotation;
		}

		interface MapShowItemsOptions {
			animate?: boolean;
			padding?: Padding;
		}

		class Padding {
			constructor(top: number, right: number, bottom: number, left: number);
		}

		function init(options: InitOptions): Promise<void>;

		interface InitOptions {
			authorizationCallback: (done: (token: string) => void) => void;
			language?: string;
		}

		const FeatureVisibility: {
			Adaptive: number;
			Hidden: number;
			Visible: number;
		};

		const ColorScheme: {
			Light: number;
			Dark: number;
		};
	}

	namespace CloudKit {
		interface CloudKitConfig {
			containers: ContainerConfig[];
		}

		interface ContainerConfig {
			containerIdentifier: string;
			apiTokenAuth: {
				apiToken: string;
				persist: boolean;
			};
			environment: 'development' | 'production';
		}

		function configure(config: CloudKitConfig): Container;

		function getDefaultContainer(): Container;

		interface Container {
			publicCloudDatabase: Database;
			setUpAuth(): Promise<UserIdentity | null>;
		}

		interface Database {
			performQuery(query: Query): Promise<QueryResponse>;
			fetchRecords(
				recordNames: string[],
				options?: { desiredKeys?: string[] }
			): Promise<RecordsResponse>;
		}

		interface Query {
			recordType: string;
			filterBy?: FilterObject[];
			sortBy?: SortDescriptor[];
		}

		interface FilterObject {
			fieldName: string;
			comparator: string;
			fieldValue: FieldValue;
		}

		interface SortDescriptor {
			fieldName: string;
			ascending: boolean;
		}

		interface FieldValue {
			value: unknown;
		}

		interface QueryResponse {
			records: CKRecord[];
			hasMoreResults?: boolean;
			continuationMarker?: string;
		}

		interface RecordsResponse {
			records: CKRecord[];
		}

		interface CKRecord {
			recordName: string;
			recordType: string;
			fields: Record<string, RecordField>;
			created?: { timestamp: number; userRecordName?: string };
			modified?: { timestamp: number; userRecordName?: string };
		}

		interface RecordField {
			value: unknown;
			type?: string;
		}

		interface UserIdentity {
			userRecordName: string;
			lookupInfo?: {
				emailAddress?: string;
				phoneNumber?: string;
			};
		}

		interface Asset {
			fileChecksum: string;
			size: number;
			downloadURL: string;
		}

		interface Reference {
			recordName: string;
			action?: string;
		}

		interface Location {
			latitude: number;
			longitude: number;
			altitude?: number;
			horizontalAccuracy?: number;
			verticalAccuracy?: number;
			course?: number;
			speed?: number;
			timestamp?: number;
		}
	}
}

export {};
