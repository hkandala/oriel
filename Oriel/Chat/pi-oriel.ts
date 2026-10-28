// pi-oriel: Oriel's chat view helper for pi, shipped inside Oriel (ui/chat-view#launch-flags).
// Oriel writes it to ~/.cache/oriel/pi-oriel-<sha8>.ts and starts pi with `-e <this file> --oriel <state.jsonl>`.
// It appends one JSON line per change to the state file: the session's transcript, a /tree move, an extension dialog
// opening or closing, pi starting or stopping work, and the session ending. Public pi events only.
// @ts-nocheck
import { appendFileSync, mkdirSync, statSync } from "node:fs";
import { dirname } from "node:path";

export default function (pi) {
	pi.registerFlag("oriel", { type: "string", description: "Oriel: the state file to append to" });
	let ui = false; // only a TUI session reports
	let path;
	const write = (line) => {
		const file = pi.getFlag("oriel");
		// The folder too: Oriel sweeps side files untouched for 30 days, and empty folders.
		if (ui && file) try {
			mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
			appendFileSync(file, JSON.stringify(line) + "\n", { mode: 0o600 });
		} catch {}
	};
	pi.on("session_start", (_event, ctx) => {
		ui = ctx.mode === "tui";
		path = ctx.sessionManager.getSessionFile();
		write({ type: "session", path });
	});
	// /tree writes nothing to the transcript: the new leaf, and the transcript's size at the move (entries after it
	// grow from that leaf).
	pi.on("session_tree", (event) => {
		let at = 0;
		try { at = statSync(path).size; } catch {}
		write({ type: "tree", leaf: event.newLeafId ?? null, at });
	});
	// Every extension's dialog; herdr's pi integration (when installed) then refuses agent.prompt meanwhile.
	pi.on("ui_prompt_start", (event) => {
		pi.events.emit("herdr:blocked", { active: true, label: event.title ?? event.kind });
		write({ type: "blocked" });
	});
	pi.on("ui_prompt_end", () => {
		pi.events.emit("herdr:blocked", { active: false });
		write({ type: "unblocked" });
	});
	pi.on("agent_start", () => write({ type: "working" }));
	pi.on("agent_settled", (_event, ctx) => ctx.isIdle() && write({ type: "idle" }));
	pi.on("session_shutdown", () => write({ type: "shutdown" }));
}
