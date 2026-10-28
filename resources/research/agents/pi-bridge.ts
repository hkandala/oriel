// Oriel chat-view spike: a side channel into a running pi TUI.
// Load per run: pi -e /tmp/oriel-research/pi/bridge.ts
// Listens on a unix socket (ORIEL_BRIDGE_SOCK, default /tmp/oriel-research/pi/bridge.sock).
// Protocol: JSON lines both ways. Every client gets every event (broadcast).
//   -> {type:"prompt", text, deliverAs?:"steer"|"followUp"}   user message, shows in the TUI
//   -> {type:"command", text:"/name x"}                       extension/template/skill commands only
//   -> {type:"abort"} | {type:"compact", instructions?} | {type:"new_session"}
//   -> {type:"set_model", provider, modelId} | {type:"set_thinking", level}
//   -> {type:"get_state"}
//   -> {type:"ui_response", id, value}                        answers approval_request / ui_request
//   <- {type:"event", event:{...pi event, trimmed}}
//   <- {type:"ui_request", id, kind:"select"|"confirm"|"input", title, options|message|placeholder, approval?:{toolName,input,toolCallId}}
//   <- {type:"ui_resolved", id, by:"client"|"tui", value}
// @ts-nocheck
import net from "node:net";
import fs from "node:fs";

const SOCK = process.env.ORIEL_BRIDGE_SOCK || "/tmp/oriel-research/pi/bridge.sock";
const GATED = new Set((process.env.ORIEL_GATE_TOOLS || "bash,write,edit").split(","));

export default function (pi) {
	let server;
	let ctx; // latest context; refreshed on every event
	const clients = new Set();
	const pending = new Map(); // id -> resolve(value) for client answers
	let seq = 0;

	const send = (obj) => {
		const line = JSON.stringify(obj) + "\n";
		for (const c of clients) c.write(line);
	};
	const reply = (c, id, ok, data) => c.write(JSON.stringify({ type: "response", id, ok, ...data }) + "\n");

	// Trim heavy fields: message_update carries the whole partial message on every token.
	const trim = (e) => {
		if (e.type === "message_update") {
			const { partial, ...ame } = e.assistantMessageEvent;
			return { type: e.type, role: e.message?.role, assistantMessageEvent: ame };
		}
		if (e.type === "model_select")
			return { type: e.type, model: `${e.model.provider}/${e.model.id}`, previous: e.previousModel && `${e.previousModel.provider}/${e.previousModel.id}`, source: e.source };
		if (e.type === "turn_end") return { type: e.type, turnIndex: e.turnIndex, messageEntryId: e.messageEntryId };
		if (e.type === "agent_end") return { type: e.type };
		if (e.type === "tool_execution_update") return { type: e.type, toolCallId: e.toolCallId, toolName: e.toolName };
		return e;
	};

	const forward = [
		"agent_start", "agent_end", "agent_settled", "turn_start", "turn_end",
		"message_start", "message_update", "message_end",
		"tool_execution_start", "tool_execution_update", "tool_execution_end",
		"model_select", "thinking_level_select", "ui_prompt_start", "ui_prompt_end",
		"session_compact", "session_tree", "input", "session_info_changed",
	];
	for (const name of forward) {
		pi.on(name, (e, c) => {
			if (c) ctx = c;
			if (clients.size) send({ type: "event", event: trim(e) });
		});
	}

	// One dialog, two answerers: the TUI dialog and every outside client. First answer wins; the
	// loser is dismissed (TUI via AbortSignal, clients via ui_resolved). `orig` is the real ctx.ui method.
	async function raceDialog(kind, orig, args, meta) {
		if (clients.size === 0) return orig(...args);
		const id = `ui-${++seq}`;
		const [title, second, opts = {}] = args;
		const ac = new AbortController();
		opts.signal?.addEventListener("abort", () => ac.abort());
		const fromClient = new Promise((resolve) => pending.set(id, resolve));
		pi.events.emit("herdr:blocked", { active: true, label: String(title).split("\n")[0] });
		send({ type: "ui_request", id, kind, title, ...(kind === "select" ? { options: second } : kind === "confirm" ? { message: second } : { placeholder: second }), timeout: opts.timeout, ...meta });
		const fromTui = orig(title, second, { ...opts, signal: ac.signal }).then((v) => ({ by: "tui", value: v }));
		const winner = await Promise.race([fromTui, fromClient.then((v) => ({ by: "client", value: v }))]);
		pending.delete(id);
		if (winner.by === "client") ac.abort();
		pi.events.emit("herdr:blocked", { active: false });
		send({ type: "ui_resolved", id, ...winner });
		return winner.value;
	}

	// ctx.ui is one shared object for all extensions (runner.uiContext), so wrapping it here
	// forwards every extension's select/confirm/input to outside clients too.
	function patchUi(ui) {
		if (ui.__oriel) return;
		for (const kind of ["select", "confirm", "input"]) {
			const orig = ui[kind].bind(ui);
			ui[kind] = (...args) => raceDialog(kind, orig, args);
			ui[kind].__orig = orig;
		}
		ui.__oriel = true;
	}

	// Tool approval (pi has none built in): a select with the tool call attached.
	pi.on("tool_call", async (e, c) => {
		if (!GATED.has(e.toolName) || !c.hasUI || clients.size === 0) return undefined;
		const orig = c.ui.select.__orig || c.ui.select.bind(c.ui);
		const v = await raceDialog("select", orig, [`Oriel bridge: allow ${e.toolName}?\n${JSON.stringify(e.input).slice(0, 300)}`, ["Allow", "Deny"], {}], { approval: { toolCallId: e.toolCallId, toolName: e.toolName, input: e.input } });
		if (v !== "Allow") return { block: true, reason: "Denied by user" };
		return undefined;
	});

	const state = () => ({
		idle: ctx?.isIdle(),
		model: ctx?.model && `${ctx.model.provider}/${ctx.model.id}`,
		thinking: pi.getThinkingLevel(),
		sessionFile: ctx?.sessionManager.getSessionFile(),
		sessionId: ctx?.sessionManager.getSessionId(),
		leafId: ctx?.sessionManager.getLeafId?.(),
		pendingMessages: ctx?.hasPendingMessages(),
		contextUsage: ctx?.getContextUsage(),
		commands: pi.getCommands().map((x) => x.name),
	});

	// Command-only APIs (newSession, fork, navigateTree) need an ExtensionCommandContext:
	// register a command and trigger it through sendUserMessage(..., {expandPromptTemplates:true}).
	pi.registerCommand("oriel-new", {
		description: "Oriel bridge: start a new session",
		handler: async (_args, cctx) => {
			await cctx.newSession();
		},
	});

	async function handle(c, msg) {
		const { id } = msg;
		try {
			switch (msg.type) {
				case "prompt": {
					const deliverAs = ctx.isIdle() ? undefined : msg.deliverAs || "steer";
					pi.sendUserMessage(msg.text, deliverAs ? { deliverAs } : undefined);
					return reply(c, id, true, { deliverAs: deliverAs || "start" });
				}
				case "command":
					pi.sendUserMessage(msg.text, { expandPromptTemplates: true, ...(ctx.isIdle() ? {} : { deliverAs: "followUp" }) });
					return reply(c, id, true, {});
				case "new_session":
					pi.sendUserMessage("/oriel-new", { expandPromptTemplates: true });
					return reply(c, id, true, {});
				case "abort":
					ctx.abort();
					return reply(c, id, true, {});
				case "compact":
					ctx.compact({ customInstructions: msg.instructions });
					return reply(c, id, true, {});
				case "set_model": {
					const m = ctx.modelRegistry.find(msg.provider, msg.modelId);
					if (!m) return reply(c, id, false, { error: "model not found" });
					return reply(c, id, await pi.setModel(m), {});
				}
				case "set_thinking":
					pi.setThinkingLevel(msg.level);
					return reply(c, id, true, { thinking: pi.getThinkingLevel() });
				case "get_state":
					return reply(c, id, true, { state: state() });
				case "ui_response": {
					const r = pending.get(msg.id);
					if (!r) return reply(c, id, false, { error: "no such request (already answered?)" });
					r(msg.value);
					return reply(c, id, true, {});
				}
				default:
					return reply(c, id, false, { error: `unknown type ${msg.type}` });
			}
		} catch (err) {
			reply(c, id, false, { error: String(err?.message || err) });
		}
	}

	pi.on("session_start", (e, c) => {
		ctx = c;
		if (c.mode !== "tui" || server) return;
		patchUi(c.ui);
		try { fs.unlinkSync(SOCK); } catch {}
		server = net.createServer((c2) => {
			clients.add(c2);
			let buf = "";
			c2.on("data", (d) => {
				buf += d;
				let i;
				while ((i = buf.indexOf("\n")) >= 0) {
					const line = buf.slice(0, i).replace(/\r$/, "");
					buf = buf.slice(i + 1);
					if (line.trim()) {
						let msg;
						try { msg = JSON.parse(line); } catch { reply(c2, null, false, { error: "bad json" }); continue; }
						handle(c2, msg);
					}
				}
			});
			c2.on("close", () => clients.delete(c2));
			c2.on("error", () => clients.delete(c2));
			c2.write(JSON.stringify({ type: "hello", state: state() }) + "\n");
		});
		server.listen(SOCK);
	});
	pi.on("session_shutdown", () => {
		for (const c of clients) c.destroy();
		clients.clear();
		server?.close();
		server = undefined;
		try { fs.unlinkSync(SOCK); } catch {}
	});
}
