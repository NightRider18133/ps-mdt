import { isEnvBrowser } from "./misc";
import { GetParentResourceName } from "./fivem";
import type { NuiEventName } from "@/constants/nuiEvents";
import { validateNuiAction } from "@/security/nuiSecurity";

const DEFAULT_TIMEOUT = 10000; // 10 seconds

// ---------------------------------------------------------------------------
// In-memory response cache. Repeated `fetchNui` calls for the same event +
// payload return the cached value instantly while the network call refreshes
// it in the background (stale-while-revalidate). Pages that do their own
// onMount fetch on every tab switch effectively become free re-renders.
//
// Read-only events get a default TTL; mutating events bypass the cache and
// invalidate related read events. Both behaviours can be overridden per call
// via the `cache` option.
// ---------------------------------------------------------------------------

interface CacheEntry {
	value: unknown;
	expires: number;
}

const responseCache = new Map<string, CacheEntry>();
const inflightCache = new Map<string, Promise<unknown>>();

const READ_PREFIXES = ["get", "fetch", "list", "view", "search", "load", "check"];
// Treat data as "fresh" for 60 s; after that we still return the stale value
// instantly and refresh in the background (SWR). Any mutating call clears
// the entire cache so this can never serve stale-after-edit data.
const DEFAULT_TTL_MS = 60_000;

function looksLikeRead(eventName: string): boolean {
	const lower = eventName.toLowerCase();
	return READ_PREFIXES.some((p) => lower.startsWith(p));
}

function cacheKey(eventName: string, data: unknown): string {
	try {
		return eventName + ":" + JSON.stringify(data ?? null);
	} catch {
		return eventName + ":<unserialisable>";
	}
}

export interface FetchNuiOptions {
	/** Override cache behaviour: false disables; number = TTL in ms. */
	cache?: false | number;
	/** When set, drop any cached entry whose key starts with one of these
	 *  event names after a successful fetch. Use on mutating endpoints to
	 *  refresh dependent reads on next access. */
	invalidates?: string[];
}

// Fire-and-forget refresh used by stale-while-revalidate.
async function refreshInBackground<T>(
	eventName: string,
	data: unknown,
	key: string,
	ttl: number,
	timeout: number,
): Promise<void> {
	const resourceName = GetParentResourceName();
	const promise = (async (): Promise<T> => {
		const controller = new AbortController();
		const timeoutId = setTimeout(() => controller.abort(), timeout);
		try {
			const resp = await fetch(`https://${resourceName}/${eventName}`, {
				method: "POST",
				headers: { "Content-Type": "application/json; charset=UTF-8" },
				body: JSON.stringify(data),
				signal: controller.signal,
			});
			clearTimeout(timeoutId);
			if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
			const value = (await resp.json()) as T;
			responseCache.set(key, { value, expires: Date.now() + ttl });
			return value;
		} finally {
			inflightCache.delete(key);
		}
	})();
	inflightCache.set(key, promise);
	try {
		await promise;
	} catch {
		// Background refresh — keep the stale value, the next foreground call
		// will retry. Don't surface the error.
	}
}

export function clearNuiCache(prefix?: string): void {
	if (!prefix) {
		responseCache.clear();
		return;
	}
	for (const key of responseCache.keys()) {
		if (key.startsWith(prefix + ":")) responseCache.delete(key);
	}
}

export async function fetchNui<T = any>(
	eventName: NuiEventName,
	data?: any,
	mockData?: T,
	timeoutOrOptions: number | FetchNuiOptions = DEFAULT_TIMEOUT,
): Promise<T> {
	const options: FetchNuiOptions =
		typeof timeoutOrOptions === "number" ? {} : timeoutOrOptions;
	const timeout =
		typeof timeoutOrOptions === "number" ? timeoutOrOptions : DEFAULT_TIMEOUT;

	// Security: Validate the event name against whitelist
	if (!validateNuiAction(eventName)) {
		console.warn("[ps-mdt] fetchNui: blocked unknown event:", eventName);
		if (mockData !== undefined) {
			return mockData;
		}
		return {} as T;
	}

	if (isEnvBrowser()) {
		return new Promise((resolve) => {
			setTimeout(() => resolve(mockData || ({} as T)), 100);
		});
	}

	// Cache lookup — only for read-style events unless explicitly enabled.
	const isRead = looksLikeRead(eventName);
	const ttl =
		options.cache === false
			? 0
			: typeof options.cache === "number"
				? options.cache
				: isRead
					? DEFAULT_TTL_MS
					: 0;

	// Mutating call: drop the entire read cache so the next page open sees
	// fresh data. Cheap (responseCache is small) and avoids the "I just
	// edited this thing but it still shows the old value" footgun.
	if (!isRead && ttl === 0) {
		responseCache.clear();
	}

	const key = ttl > 0 ? cacheKey(eventName, data) : "";

	if (ttl > 0) {
		const hit = responseCache.get(key);
		const inflight = inflightCache.get(key);

		// Fresh hit — return instantly, no network call.
		if (hit && hit.expires > Date.now()) {
			return hit.value as T;
		}

		// Stale-while-revalidate: if we have an old value but no in-flight
		// refresh, kick one off in the background and return the stale value
		// immediately. The cache is updated when the refresh resolves, so
		// the next visit gets the fresh data with zero perceived latency.
		if (hit && !inflight) {
			void refreshInBackground<T>(eventName, data, key, ttl, timeout);
			return hit.value as T;
		}

		// In-flight — share the request rather than firing a duplicate.
		if (inflight) return inflight as Promise<T>;
	}

	const resourceName = GetParentResourceName();

	const networkPromise = (async (): Promise<T> => {
		try {
			const controller = new AbortController();
			const timeoutId = setTimeout(() => controller.abort(), timeout);

			const resp = await fetch(`https://${resourceName}/${eventName}`, {
				method: "POST",
				headers: { "Content-Type": "application/json; charset=UTF-8" },
				body: JSON.stringify(data),
				signal: controller.signal,
			});
			clearTimeout(timeoutId);

			if (!resp.ok) throw new Error(`HTTP error! status: ${resp.status}`);
			const value = (await resp.json()) as T;

			if (ttl > 0) {
				responseCache.set(key, { value, expires: Date.now() + ttl });
			}
			if (options.invalidates) {
				for (const prefix of options.invalidates) clearNuiCache(prefix);
			}

			return value;
		} catch (err) {
			if (err instanceof DOMException && err.name === "AbortError") {
				console.warn(
					`[ps-mdt] fetchNui timed out after ${timeout}ms:`,
					eventName,
				);
				return {} as T;
			}
			throw err;
		} finally {
			if (key) inflightCache.delete(key);
		}
	})();

	if (key) inflightCache.set(key, networkPromise);
	return networkPromise;
}
