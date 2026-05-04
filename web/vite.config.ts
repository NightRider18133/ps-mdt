import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import tailwindcss from "@tailwindcss/vite";

// https://vite.dev/config/
export default defineConfig({
	plugins: [svelte(), tailwindcss()],
	base: "./",
	resolve: {
		alias: {
			"@/": "/src/",
			$lib: "/src/lib",
			src: "/src",
		},
	},
	build: {
		// Tiptap + yjs + leaflet push the bundle past Vite's default 500 KB
		// warning; the single-chunk layout is required because tiptap and
		// y-prosemirror have circular imports across modules that break when
		// rollup splits them into separate chunks (initialization order
		// produces "Cannot access 'X' before initialization").
		chunkSizeWarningLimit: 1500,
	},
});
