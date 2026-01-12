import type { Cafe } from "./types";
import { getPriceCategory, formatPrice } from "./types";

let mapKitInitialized = false;
let initPromise: Promise<void> | null = null;

export async function initMapKit(token: string): Promise<void> {
  if (mapKitInitialized) return;

  if (initPromise) {
    return initPromise;
  }

  initPromise = new Promise((resolve, reject) => {
    if (typeof window === "undefined") {
      reject(new Error("MapKit can only be initialized in the browser"));
      return;
    }

    const checkMapKit = () => {
      if (window.mapkit) {
        window.mapkit.init({
          authorizationCallback: (done) => {
            done(token);
          },
          language: "de",
        });
        mapKitInitialized = true;
        resolve();
      } else {
        setTimeout(checkMapKit, 100);
      }
    };
    checkMapKit();
  });

  return initPromise;
}

export function createMap(container: HTMLElement): mapkit.Map {
  const map = new window.mapkit.Map(container, {
    showsCompass: "adaptive" as unknown as mapkit.FeatureVisibility,
    showsScale: "adaptive" as unknown as mapkit.FeatureVisibility,
    showsMapTypeControl: false,
    showsUserLocationControl: true,
    colorScheme: "light" as unknown as mapkit.ColorScheme,
  });

  // Default to Germany/Europe
  map.region = new window.mapkit.CoordinateRegion(
    new window.mapkit.Coordinate(51.1657, 10.4515),
    new window.mapkit.CoordinateSpan(8, 12),
  );

  return map;
}

export function createCafeAnnotation(
  cafe: Cafe,
  onClick: (cafe: Cafe) => void,
): mapkit.Annotation {
  const category = getPriceCategory(cafe.currentPrice);

  const annotation = new window.mapkit.Annotation(
    new window.mapkit.Coordinate(cafe.latitude, cafe.longitude),
    () => {
      const element = document.createElement("div");
      element.className = `price-marker ${category}`;
      element.textContent = formatPrice(cafe.currentPrice);
      return element;
    },
    {
      title: cafe.name,
      subtitle: cafe.address,
      data: { cafe },
    },
  );

  annotation.addEventListener("select", () => {
    onClick(cafe);
  });

  return annotation;
}

export function addCafesToMap(
  map: mapkit.Map,
  cafes: Cafe[],
  onClick: (cafe: Cafe) => void,
): mapkit.Annotation[] {
  // Clear existing annotations
  map.removeAnnotations(map.annotations);

  const annotations = cafes.map((cafe) => createCafeAnnotation(cafe, onClick));
  map.addAnnotations(annotations);

  // Zoom to show all cafes if there are any
  if (annotations.length > 0) {
    map.showItems(annotations, {
      animate: true,
      padding: new window.mapkit.Padding(50, 50, 50, 50),
    });
  }

  return annotations;
}

export function focusOnCafe(map: mapkit.Map, cafe: Cafe): void {
  map.region = new window.mapkit.CoordinateRegion(
    new window.mapkit.Coordinate(cafe.latitude, cafe.longitude),
    new window.mapkit.CoordinateSpan(0.01, 0.01),
  );
}
