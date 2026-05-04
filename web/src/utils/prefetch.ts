import { fetchNui } from "./fetchNui";
import { NUI_EVENTS, type NuiEventName } from "@/constants/nuiEvents";

// Pages users hit most often. Firing these the moment auth completes warms
// the fetchNui cache so the first click on each tab renders immediately.
//
// All entries must be read-style events (the cache only stores reads).
const COMMON_PREFETCHES: Array<{ event: NuiEventName; payload?: unknown }> = [
	{ event: NUI_EVENTS.CITIZEN.GET_CITIZENS, payload: { page: 1 } },
	{ event: NUI_EVENTS.VEHICLE.GET_VEHICLES, payload: { page: 1, perPage: 25 } },
	{ event: NUI_EVENTS.WEAPON.GET_WEAPONS, payload: { page: 1, perPage: 25 } },
	{ event: NUI_EVENTS.CITIZEN.GET_BOLOS },
	{ event: NUI_EVENTS.DASHBOARD.GET_ACTIVE_WARRANTS },
	{ event: NUI_EVENTS.CASE.GET_CASES },
	{ event: NUI_EVENTS.CHARGE.GET_CHARGES },
];

let started = false;

/**
 * Fire common page reads in parallel after auth so the cache is warm by the
 * time the user clicks any of these tabs. Safe to call multiple times — only
 * the first invocation per session does work.
 */
export function prefetchCommonPages(): void {
	if (started) return;
	started = true;

	// Fire all in parallel; ignore failures (the page itself will retry).
	for (const { event, payload } of COMMON_PREFETCHES) {
		try {
			void fetchNui(event, payload).catch(() => {});
		} catch {
			// Some events may not exist on certain frameworks; skip silently.
		}
	}
}
