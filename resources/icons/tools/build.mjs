// Builds resources/icons (svg/, catalog.json, SOURCES.md, licenses/, contact-sheet.png). See tools/README.md.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WORK = process.env.ICONS_WORK ?? '/tmp/icons-work';
const NM = `${WORK}/node_modules`;
const require = createRequire(`${NM}/`);
const si = require('simple-icons');
const paper = require('paper-jsdom');
const { Resvg } = require('@resvg/resvg-js');
const svgpath = require('svgpath');
const ver = (p) => JSON.parse(fs.readFileSync(`${NM}/${p}/package.json`)).version;

const NEUTRAL = '#2b2d31', GREEN = '#7ee787', GRAY = '#8b8d91', WHITE = '#ffffff', INK = '#111111';

const SRC = {
  si: { name: 'Simple Icons', license: 'CC0-1.0', file: (s) => `${NM}/simple-icons/icons/${s}.svg`, url: (s) => `https://github.com/simple-icons/simple-icons/blob/develop/icons/${s}.svg` },
  lobe: { name: 'Lobe Icons', license: 'MIT', file: (s) => `${NM}/@lobehub/icons-static-svg/icons/${s}.svg`, url: (s) => `https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/${s}.svg)` },
  ph: { name: 'Phosphor Icons', license: 'MIT', file: (s) => `${NM}/@phosphor-icons/core/assets/fill/${s}-fill.svg`, url: (s) => `https://phosphoricons.com/?q=${s} (@phosphor-icons/core assets/fill/${s}-fill.svg)` },
  devicon: { name: 'Devicon', license: 'MIT', file: (s) => `${NM}/devicon/icons/${s}`, url: (s) => `https://github.com/devicons/devicon/blob/master/icons/${s}` },
  ext: { file: (s) => `${OUT}/tools/ext/${s}` },
  orig: { name: 'original', license: 'CC0-1.0', url: () => '' },
};
const EXT = {
  omp: ['oh-my-pi repo', 'MIT', 'https://github.com/can1357/oh-my-pi/blob/main/packages/collab-web/public/favicon.svg'],
  aider: ['aider repo', 'Apache-2.0', 'https://github.com/Aider-AI/aider/blob/main/aider/website/assets/icons/safari-pinned-tab.svg'],
  jj: ['jj repo', 'Apache-2.0', 'https://github.com/jj-vcs/jj/blob/main/docs/images/jj-logo.svg'],
};

// Originals: solid geometric marks on a 24 grid. Shapes paint in order; fill="#fff" shapes cut holes.
const o = (body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">${body}</svg>`;
const ring = (cx, cy, R, r) => `<circle cx="${cx}" cy="${cy}" r="${R}"/><circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/>`;
const arch = (x) => `${ring(x + 5, 11, 5, 1.5)}<rect x="${x}" y="11" width="10" height="9" fill="#fff"/><rect x="${x}" y="6" width="3.5" height="14"/><rect x="${x + 6.5}" y="11" width="3.5" height="9"/>`;
const ORIG = {
  letta: o('<path d="M5 2h4.5v15.5H19V22H5z"/>'),
  hermes: o('<path d="M3.5 2H8v7.75h8V2h4.5v20H16v-7.75H8V22H3.5z"/>'),
  maki: o('<path d="M2 22V2h4.5L12 10l5.5-8H22v20h-4.5V9.5L12 17 6.5 9.5V22z"/>'),
  dotnet: o('<path d="M3 22V2h4.5l9 12.5V2H21v20h-4.5l-9-12.5V22z"/>'),
  crush: o(`${ring(12, 12, 10, 5.5)}<path d="M12 12 24 3.5v17z" fill="#fff"/>`),
  go: o(`${ring(12, 12, 10, 5.5)}<path d="M12 10.5 24 1v9.5z" fill="#fff"/><path d="M12.5 10.5H22V14.5H12.5z"/><path d="M17.5 10.5H22V18h-4.5z"/>`),
  nushell: o(`${arch(1)}<g transform="rotate(180 18 13)">${arch(13)}</g>`),
  sleep: o('<path d="M2 9h11v3.5L7.5 18.5H13V22H2v-3.5L7.5 12.5H2z"/><path d="M14 2h8v2.6l-4 4.3h4v2.6h-8V8.9l4-4.3h-4z"/>'),
};

// [id, title, kind, src, match, extra]. extra: brandColor, generic (dark tile + green glyph), knock (colors that cut holes),
// keep (filter subpaths by source bounds), size (override fit), bold (thicken by this many units at 24), notes.
const E = [
  // agents
  ['pi', 'Pi', 'agent', 'si:pi', { agent: ['pi'], process: ['pi'], titlePrefix: ['π'], scriptSuffix: ['pi-coding-agent/dist/cli.js', 'pi-coding-agent/dist/bundle/cli.js'] }],
  ['omp', 'Oh My Pi', 'agent', 'ext:omp-mark.svg', { agent: ['omp'], process: ['omp'] }, { brandColor: '#9b4dff', notes: 'pi glyph path from the favicon; dark rect and gradient dropped' }],
  ['claude', 'Claude Code', 'agent', 'si:claudecode', { agent: ['claude'], process: ['claude', 'claude.exe'], titlePrefix: ['Claude Code'], scriptSuffix: ['@anthropic-ai/claude-code/cli.js'] }],
  ['codex', 'Codex', 'agent', 'lobe:codex', { agent: ['codex'], process: ['codex'], scriptSuffix: ['@openai/codex/bin/codex.js'] }, { brandColor: '#3941ff' }],
  ['copilot', 'GitHub Copilot CLI', 'agent', 'si:githubcopilot', { agent: ['copilot'], process: ['copilot'], scriptSuffix: ['copilot/npm-loader.js', '@github/copilot/index.js'] }],
  ['devin', 'Devin', 'agent', 'lobe:devin', { agent: ['devin'], process: ['devin'] }, { brandColor: '#0294de' }],
  ['droid', 'Droid (Factory)', 'agent', 'ph:robot', { agent: ['droid'], process: ['droid'] }, { brandColor: '#000000', notes: 'Factory publishes no permissive logo (Factory-AI/factory has no license); generic robot glyph' }],
  ['kimi', 'Kimi Code', 'agent', 'si:kimi', { agent: ['kimi'], process: ['kimi', 'kimi-cli'] }],
  ['opencode', 'OpenCode', 'agent', 'si:opencode', { agent: ['opencode'], process: ['opencode'] }],
  ['kilo', 'Kilo Code', 'agent', 'lobe:kilocode', { agent: ['kilo'], process: ['kilo', 'kilocode'] }, { brandColor: '#f8f675' }],
  ['hermes', 'Hermes Agent', 'agent', 'orig', { agent: ['hermes'], process: ['hermes'] }, { brandColor: '#000000', notes: 'the Lobe mark is a detailed portrait that reads as a blob at tab size; solid "H" monogram' }],
  ['qoder', 'Qoder', 'agent', 'lobe:qoder', { agent: ['qodercli'], process: ['qodercli', 'qoder'] }, { brandColor: '#2adb5c' }],
  ['qwen', 'Qwen Code', 'agent', 'si:qwen', { agent: ['qwen'], process: ['qwen'], scriptSuffix: ['@qwen-code/qwen-code/cli-entry.js', '@qwen-code/qwen-code/cli.js'] }],
  ['cursor', 'Cursor Agent', 'agent', 'si:cursor', { agent: ['cursor'], process: ['cursor-agent', 'agent'] }],
  ['mastra', 'Mastra Code', 'agent', 'lobe:mastra', { agent: ['mastracode'], process: ['mastracode', 'mastra'] }, { brandColor: '#000000' }],
  ['antigravity', 'Google Antigravity', 'agent', 'lobe:antigravity', { agent: ['agy', 'antigravity_cli'], process: ['agy', 'antigravity'] }, { brandColor: '#3186ff' }],
  ['grok', 'Grok', 'agent', 'lobe:grok', { agent: ['grok'], process: ['grok'] }, { brandColor: '#000000' }],
  ['letta', 'Letta Code', 'agent', 'orig', { agent: ['letta'], process: ['letta'] }, { brandColor: '#000000', notes: 'no logo SVG in letta-ai repos and none in Simple Icons/Lobe; solid "L" monogram' }],
  ['gemini', 'Gemini CLI', 'agent', 'si:googlegemini', { agent: ['gemini'], process: ['gemini'], scriptSuffix: ['@google/gemini-cli/bundle/gemini.js', '@google/gemini-cli/dist/index.js'] }],
  ['amp', 'Amp', 'agent', 'lobe:amp', { agent: ['amp'], process: ['amp'] }, { brandColor: '#f34e3f', notes: 'Simple Icons "amp" is the AMP web project, not Sourcegraph Amp' }],
  ['goose', 'Goose', 'agent', 'lobe:goose', { process: ['goose'] }, { brandColor: '#000000' }],
  ['aider', 'Aider', 'agent', 'ext:aider-mark.svg', { process: ['aider'] }, { brandColor: '#14b014', notes: 'outer square removed so the mark is the glyph (was a knock-out)' }],
  ['crush', 'Crush', 'agent', 'orig', { process: ['crush'] }, { brandColor: '#6b50ff', notes: 'charmbracelet/crush is FSL-1.1, no permissive logo; solid "C" monogram' }],
  ['ollama', 'Ollama', 'agent', 'si:ollama', { process: ['ollama'] }],
  ['cline', 'Cline', 'agent', 'si:cline', { agent: ['cline'], process: ['cline'] }],
  ['kiro', 'Kiro', 'agent', 'lobe:kiro', { agent: ['kiro'], process: ['kiro-cli', 'kiro'] }, { brandColor: '#9046ff' }],
  ['maki', 'Maki', 'agent', 'orig', { agent: ['maki'], process: ['maki'] }, { brandColor: '#000000', notes: 'unknown brand; solid "M" monogram' }],
  ['poolside', 'Poolside', 'agent', 'lobe:poolside', { process: ['pool', 'poolside'] }, { brandColor: '#4137ff' }],
  ['openclaw', 'OpenClaw', 'agent', 'lobe:openclaw', { process: ['openclaw'] }, { brandColor: '#ff4d4d' }],
  ['mistral', 'Mistral Vibe', 'agent', 'si:mistralai', { process: ['vibe'], titlePrefix: ['Vibe'] }],
  // shells
  ['terminal', 'Shell', 'shell', 'ph:terminal-window', { process: ['sh', 'dash', 'ksh', 'tcsh', 'csh', 'login'] }, { notes: 'fallback for any unmatched pane' }],
  ['zsh', 'zsh', 'shell', 'si:zsh', { process: ['zsh', '-zsh'] }],
  ['bash', 'bash', 'shell', 'si:gnubash', { process: ['bash', '-bash'] }],
  ['fish', 'fish', 'shell', 'ph:fish-simple', { process: ['fish', '-fish'] }, { notes: 'the fish shell mark is thin lines that vanish at 1x; generic fish glyph' }],
  ['nushell', 'Nushell', 'shell', 'orig', { process: ['nu'] }, { brandColor: '#4e9a06', notes: 'the Nushell mark is the "nu>" wordmark; solid "nu" monogram' }],
  // editors
  ['vim', 'Vim', 'editor', 'si:vim', { process: ['vim', 'vi', 'view', 'vimdiff', 'gvim'] }],
  ['neovim', 'Neovim', 'editor', 'si:neovim', { process: ['nvim'] }],
  ['helix', 'Helix', 'editor', 'si:helix', { process: ['hx', 'helix'] }],
  ['emacs', 'Emacs', 'editor', 'si:gnuemacs', { process: ['emacs', 'emacsclient'] }],
  ['nano', 'nano', 'editor', 'si:nano', { process: ['nano', 'pico'] }],
  ['pager', 'Pager / man', 'tool', 'ph:book-open', { process: ['less', 'more', 'most', 'man'] }, { generic: true }],
  ['bat', 'bat', 'tool', 'si:bat', { process: ['bat'] }],
  // git
  ['git', 'Git', 'tool', 'si:git', { process: ['git'] }],
  ['lazygit', 'lazygit', 'tool', 'ph:git-diff', { process: ['lazygit'] }, { generic: true, brandColor: '#3fb950', notes: 'no lazygit logo SVG; generic git-changes glyph' }],
  ['tig', 'tig', 'tool', 'ph:git-commit', { process: ['tig'] }, { generic: true, brandColor: '#f03c2e', notes: 'no tig logo; generic commit glyph' }],
  ['github', 'GitHub CLI', 'tool', 'si:github', { process: ['gh'] }],
  ['jj', 'Jujutsu', 'tool', 'ext:jj-flat.svg', { process: ['jj', 'jjui', 'lazyjj'] }, { brandColor: '#2f9fdf', knock: ['#e9f2f1'], notes: 'full-color logo turned into one silhouette: all colors filled, the light parts cut out' }],
  // system
  ['monitor', 'Monitor', 'tool', 'ph:gauge', { process: ['top', 'htop', 'btop', 'btm', 'atop', 'glances', 'gotop', 'nvtop', 'asitop'] }, { generic: true }],
  ['ssh', 'SSH', 'tool', 'ph:key', { process: ['ssh', 'mosh', 'mosh-client', 'et', 'autossh'] }, { generic: true }],
  ['logs', 'Logs', 'tool', 'ph:scroll', { process: ['tail', 'log', 'journalctl', 'lnav'] }, { generic: true }],
  ['sleep', 'Sleep', 'tool', 'orig', { process: ['sleep', 'caffeinate', 'wait'] }, { generic: true, notes: 'solid zZ glyph (Phosphor has none)' }],
  ['tmux', 'tmux', 'tool', 'si:tmux', { process: ['tmux', 'zellij', 'screen'] }],
  ['yazi', 'Yazi', 'tool', 'ph:folder-open', { process: ['yazi', 'ranger', 'lf', 'nnn', 'mc'] }, { generic: true, brandColor: '#e7904a', notes: 'no yazi logo SVG; generic file-manager glyph' }],
  // containers / cloud
  ['docker', 'Docker', 'tool', 'si:docker', { process: ['docker', 'docker-compose', 'lazydocker', 'colima'] }],
  ['podman', 'Podman', 'tool', 'ph:package', { process: ['podman'] }, { brandColor: '#892ca0', notes: 'the Podman seal is fine detail that reads as a blob at 1x; generic container glyph' }],
  ['kubernetes', 'Kubernetes', 'tool', 'si:kubernetes', { process: ['kubectl', 'kubectx', 'kubens', 'k9s', 'helm', 'minikube', 'kind'] }, { notes: 'k9s has no permissive SVG mark; shares the Kubernetes wheel' }],
  ['terraform', 'Terraform', 'tool', 'si:terraform', { process: ['terraform', 'tofu'] }],
  ['packer', 'Packer', 'tool', 'si:packer', { process: ['packer'] }],
  ['nomad', 'Nomad', 'tool', 'si:nomad', { process: ['nomad'] }],
  ['vagrant', 'Vagrant', 'tool', 'si:vagrant', { process: ['vagrant'] }],
  ['vault', 'Vault', 'tool', 'si:vault', { process: ['vault'] }],
  ['consul', 'Consul', 'tool', 'si:consul', { process: ['consul'] }],
  ['aws', 'AWS CLI', 'tool', 'lobe:aws', { process: ['aws', 'sam', 'cdk'] }, { brandColor: '#ff9900', keep: (b) => b.top > 13, bold: 0.35, notes: '"aws" letters dropped; the smile arrow alone, thickened for 1x' }],
  ['gcloud', 'Google Cloud', 'tool', 'si:googlecloud', { process: ['gcloud', 'gsutil', 'bq'] }],
  ['azure', 'Azure CLI', 'tool', 'lobe:azure', { process: ['az'] }, { brandColor: '#0669bc' }],
  ['vercel', 'Vercel', 'tool', 'si:vercel', { process: ['vercel', 'vc'] }],
  ['cloudflare', 'Cloudflare', 'tool', 'si:cloudflare', { process: ['wrangler', 'cloudflared'] }],
  ['heroku', 'Heroku', 'tool', 'devicon:heroku/heroku-plain.svg', { process: ['heroku'] }, { brandColor: '#6762a6', notes: 'not in Simple Icons or Lobe' }],
  ['railway', 'Railway', 'tool', 'si:railway', { process: ['railway'] }],
  ['render', 'Render', 'tool', 'si:render', { process: ['render'] }],
  ['modal', 'Modal', 'tool', 'si:modal', { process: ['modal'] }],
  ['tailscale', 'Tailscale', 'tool', 'si:tailscale', { process: ['tailscale'] }],
  ['stripe', 'Stripe', 'tool', 'si:stripe', { process: ['stripe'] }],
  ['sanity', 'Sanity', 'tool', 'si:sanity', { process: ['sanity'] }],
  ['buildkite', 'Buildkite', 'tool', 'si:buildkite', { process: ['bk', 'buildkite-agent'] }],
  ['bazel', 'Bazel', 'tool', 'si:bazel', { process: ['bazel', 'bazelisk'] }],
  ['nix', 'Nix', 'tool', 'si:nixos', { process: ['nix', 'nh', 'nom', 'nix-build', 'nix-env', 'nix-shell', 'nix-store', 'darwin-rebuild', 'nixos-rebuild'] }],
  ['homebrew', 'Homebrew', 'tool', 'si:homebrew', { process: ['brew'] }],
  ['huggingface', 'Hugging Face', 'tool', 'si:huggingface', { process: ['huggingface-cli', 'hf'] }],
  ['moon', 'moon', 'tool', 'si:moonrepo', { process: ['moon'] }],
  // build / packages
  ['make', 'GNU make / gcc', 'tool', 'ph:hammer', { process: ['make', 'gmake', 'configure', 'libtool', 'gcc', 'g++', 'cpp', 'cc'] }, { generic: true, notes: 'the GNU head is detailed art that reads as a blob at tab size; generic build glyph' }],
  ['npm', 'npm', 'tool', 'si:npm', { process: ['npm', 'npx'] }],
  ['pnpm', 'pnpm', 'tool', 'si:pnpm', { process: ['pnpm', 'pnpx'] }],
  ['yarn', 'Yarn', 'tool', 'si:yarn', { process: ['yarn'] }],
  ['vite', 'Vite', 'tool', 'si:vite', { process: ['vite', 'vitest'] }],
  // databases
  ['postgres', 'PostgreSQL', 'tool', 'si:postgresql', { process: ['psql', 'postgres', 'pgcli', 'pg_dump', 'pg_restore'] }, { bold: 0.3, notes: 'thickened: its thin outlines vanish at 1x' }],
  ['sqlite', 'SQLite', 'tool', 'si:sqlite', { process: ['sqlite3', 'sqlite', 'litecli'] }],
  ['database', 'Database', 'tool', 'ph:database', { process: ['mysql', 'mariadb', 'mycli', 'redis-cli', 'mongosh', 'mongo', 'duckdb', 'clickhouse', 'usql'] }, { generic: true, notes: 'generic database glyph' }],
  // languages
  ['python', 'Python', 'language', 'si:python', { process: ['python', 'python2', 'python2.7', 'python3', 'python3.10', 'python3.11', 'python3.12', 'python3.13', 'python3.14', 'python3.15', 'ipython', 'pip', 'pip3'] }],
  ['uv', 'uv', 'language', 'si:uv', { process: ['uv', 'uvx'] }],
  ['jupyter', 'Jupyter', 'language', 'ph:planet', { process: ['jupyter', 'jupyter-notebook', 'jupyter-lab', 'jupyter-console', 'jupyter-qtconsole'] }, { brandColor: '#f37626', notes: 'the Jupyter orbits are thin at 1x; generic planet glyph' }],
  ['node', 'Node.js', 'language', 'si:nodedotjs', { process: ['node'] }],
  ['bun', 'Bun', 'language', 'si:bun', { process: ['bun', 'bunx'] }],
  ['deno', 'Deno', 'language', 'si:deno', { process: ['deno'] }],
  ['ruby', 'Ruby', 'language', 'si:ruby', { process: ['ruby', 'irb', 'bundle', 'bundler', 'rails', 'rake', 'gem'] }],
  ['go', 'Go', 'language', 'orig', { process: ['go', 'gopls', 'dlv'] }, { brandColor: '#00add8', notes: 'Simple Icons "go" is the GO wordmark; solid "G" monogram' }],
  ['rust', 'Rust', 'language', 'si:rust', { process: ['cargo', 'rustc', 'rustup', 'bacon'] }],
  ['java', 'Java', 'language', 'ph:coffee', { process: ['java', 'javac', 'jshell', 'gradle', 'mvn'] }, { brandColor: '#e76f00', notes: 'the OpenJDK mark is thin at 1x; generic coffee cup in Java orange' }],
  ['swift', 'Swift', 'language', 'si:swift', { process: ['swift', 'swiftc', 'xcodebuild', 'xcrun'] }],
  ['zig', 'Zig', 'language', 'si:zig', { process: ['zig'] }],
  ['clang', 'Clang / LLVM', 'language', 'si:llvm', { process: ['clang', 'clang++', 'clang-cpp', 'clang-cl', 'lldb', 'clangd'] }],
  ['dart', 'Dart', 'language', 'si:dart', { process: ['dart', 'pub'] }],
  ['flutter', 'Flutter', 'language', 'si:flutter', { process: ['flutter'] }],
  ['dotnet', '.NET', 'language', 'orig', { process: ['dotnet'] }, { brandColor: '#512bd4', notes: 'Simple Icons "dotnet" is the .NET wordmark; solid "N" monogram' }],
  // generic
  ['placeholder', 'Placeholder', 'generic', 'ph:circle-dashed', {}, { generic: true, notes: 'shown while the program is unknown/loading; gray glyph' }],
];

// ---- geometry: import, union fills / cut knock-outs, fit into 24x24 --------------------------------
paper.setup(new paper.Size(64, 64));
const clean = (s) => s
  .replace(/<\?xml[^>]*>|<!DOCTYPE[^>]*>|<!--.*?-->|<title>.*?<\/title>|<metadata>.*?<\/metadata>/gs, '')
  .replace(/<(mask|clipPath)\b.*?<\/\1>/gs, '').replace(/ (mask|clip-path|style)="[^"]*"/g, '')
  .replace(/<svg\b[^>]*>/, (t) => t.replace(/ (width|height)="[^"]*"/g, ''))
  .replace(/currentColor/g, '#000000').replace(/<svg\b(?![^>]*\bfill=)/, '<svg fill="#000000"') // SVG default fill is black
  .replace(/ d="([^"]*)"/g, (_, d) => ` d="${svgpath(d).unarc().toString()}"`); // paper misreads packed arc flags

function shape(svg, { knock = [], keep }) {
  const root = paper.project.importSVG(clean(svg), { expandShapes: true, insert: false });
  const knocks = new Set(['#ffffff', ...knock]);
  let acc = null;
  const walk = (it, op) => {
    const alpha = op * it.opacity;
    if (it.children && !(it instanceof paper.CompoundPath)) return it.children.forEach((c) => walk(c, alpha));
    if (!(it instanceof paper.PathItem) || it.clipMask || !it.fillColor || alpha * it.fillColor.alpha < 0.2) return;
    const p = it.clone({ insert: false });
    p.transform(it.parent.globalMatrix);
    const cut = it.fillColor.type === 'rgb' && knocks.has(it.fillColor.toCSS(true));
    acc = cut ? acc?.subtract(p, { insert: false }) ?? null : acc ? acc.unite(p, { insert: false }) : p.unite(p, { insert: false });
  };
  walk(root, 1);
  if (keep) acc = new paper.CompoundPath({ children: (acc.children ?? [acc]).filter((c) => keep(c.bounds)).map((c) => c.clone({ insert: false })), insert: false });
  return acc.reduce();
}

function raster(d, px) {
  const img = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="${d}"/></svg>`, { fitTo: { mode: 'width', value: px } }).render();
  let n = 0, sx = 0, sy = 0;
  for (let i = 3; i < img.pixels.length; i += 4) if (img.pixels[i]) { const a = img.pixels[i] / 255, k = (i - 3) / 4; n += a; sx += a * (k % px); sy += a * Math.floor(k / px); }
  return { ink: n, cx: (sx / n + 0.5) * 24 / px, cy: (sy / n + 0.5) * 24 / px };
}

// Fit: wide/tall marks to ~18, square ones to ~16, dense ones a bit smaller, light ones a bit larger;
// center halfway between the bounding box center and the ink centroid (optical centering).
function fit(p, size) {
  let b = p.bounds;
  const aspect = Math.max(b.width, b.height) / Math.min(b.width, b.height);
  p.scale(16 / Math.max(b.width, b.height), b.center); p.position = new paper.Point(12, 12);
  b = p.bounds;
  const r = raster(p.pathData, 96), density = r.ink / (b.width * b.height * 16);
  const T = size ?? Math.min(18.5, Math.max(15, 16 + Math.min(1, (aspect - 1) / 0.5) * 2 + (0.5 - density) * 2));
  p.scale(T / 16, new paper.Point(12, 12));
  const k = T / 16, c = b.center;
  p.translate(new paper.Point(-(r.cx - c.x) * k * 0.5, -(r.cy - c.y) * k * 0.5));
  return { T, density };
}

// ---- tiles ------------------------------------------------------------------------------------------
const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
const hex = (c) => '#' + c.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join('');
const lum = (h) => { const c = rgb(h).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
function hsl(h) {
  const [r, g, b] = rgb(h), mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
  if (!d) return [0, 0, l];
  const s = d / (1 - Math.abs(2 * l - 1));
  const hu = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [(hu * 60 + 360) % 360, s, l];
}
function fromHsl([h, s, l]) {
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return hex([r + m, g + m, b + m]);
}
// Brand tile: calm the color (saturation <= 0.75); if white is just short of 3:1, darken up to 12 points;
// white glyph when it reaches 3:1, else #111111. Near-black/near-white brands and generic glyphs: neutral tile.
function tileFor(brand, generic, id) {
  if (id === 'placeholder') return { background: NEUTRAL, glyph: GRAY };
  if (generic) return { background: NEUTRAL, glyph: GREEN };
  if (lum(brand) < 0.02 || lum(brand) > 0.8) return { background: NEUTRAL, glyph: WHITE };
  let [h, s, l] = hsl(brand);
  s = Math.min(s, 0.75);
  let bg = fromHsl([h, s, l]);
  for (let d = 0; contrast(bg, WHITE) < 3 && contrast(bg, WHITE) >= 2.2 && d < 0.12; d += 0.01) bg = fromHsl([h, s, l - d - 0.01]);
  return { background: bg, glyph: contrast(bg, WHITE) >= 3 ? WHITE : INK };
}

// ---- build ------------------------------------------------------------------------------------------
fs.rmSync(path.join(OUT, 'svg'), { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'svg'), { recursive: true });
const catalog = [], rows = [], fits = [];
for (const [id, title, kind, src, match, x = {}] of E) {
  const [type, arg] = src.split(/:(.*)/s);
  let raw, source, license, url, brandColor = x.brandColor;
  if (type === 'orig') { raw = ORIG[id]; ({ name: source, license } = SRC.orig); url = ''; }
  else if (type === 'ext') { raw = fs.readFileSync(SRC.ext.file(arg), 'utf8'); [source, license, url] = EXT[id]; }
  else { raw = fs.readFileSync(SRC[type].file(arg), 'utf8'); ({ name: source, license } = SRC[type]); url = SRC[type].url(arg); }
  if (type === 'si') brandColor ??= '#' + Object.values(si).find((i) => i?.slug === arg).hex;
  let p; try { p = shape(raw, x); } catch (e) { throw new Error(`${id}: ${e.message}`); }
  const f = fit(p, x.size);
  // Thicken: the union of copies shifted around a circle of radius `bold`.
  if (x.bold) for (let k = 0; k < 16; k++) { const t = (k * Math.PI) / 8; p = p.unite(p.clone({ insert: false }).translate(new paper.Point(Math.cos(t) * x.bold, Math.sin(t) * x.bold)), { insert: false }); }
  fits.push(`${id}:${f.T.toFixed(1)}/${f.density.toFixed(2)}`);
  fs.writeFileSync(path.join(OUT, 'svg', `${id}.svg`), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="${p.getPathData(null, 2)}"/></svg>\n`);
  const generic = kind === 'shell' || !!x.generic;
  brandColor = (brandColor ?? NEUTRAL).toLowerCase();
  const m = {};
  for (const k of ['agent', 'process', 'titlePrefix', 'scriptSuffix']) if (match[k]?.length) m[k] = match[k];
  catalog.push({ id, title, kind, match: m, svg: `svg/${id}.svg`, monochrome: true, brandColor, tile: tileFor(brandColor, generic, id), source, license, url });
  rows.push(`| ${id} | ${source} | ${license} | ${url || '—'} | ${x.notes ?? ''} |`);
}
fs.writeFileSync(path.join(OUT, 'catalog.json'), JSON.stringify(catalog, null, 2) + '\n');

// ---- the app's asset catalog: one template image set per icon, vector data kept -------------------------
const ASSETS = path.resolve(OUT, '../../Oriel/Assets.xcassets');
for (const f of fs.readdirSync(ASSETS)) if (f.startsWith('program.')) fs.rmSync(path.join(ASSETS, f), { recursive: true });
for (const c of catalog) {
  const dir = path.join(ASSETS, `program.${c.id}.imageset`);
  fs.mkdirSync(dir);
  fs.copyFileSync(path.join(OUT, c.svg), path.join(dir, `${c.id}.svg`));
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: `${c.id}.svg`, idiom: 'universal' }], info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': c.monochrome ? 'template' : 'original' },
  }, null, 2) + '\n');
}

// ---- licenses + SOURCES.md --------------------------------------------------------------------------
const LIC = {
  'Simple Icons': ['simple-icons-CC0-1.0.md', `${NM}/simple-icons/LICENSE.md`, `CC0-1.0, package simple-icons@${ver('simple-icons')}. Simple Icons asks users to check each brand's guidelines: https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md`],
  'Lobe Icons': ['lobe-icons-MIT.txt', `${WORK}/lic/lobe.txt`, `MIT, Copyright (c) 2023 LobeHub, package @lobehub/icons-static-svg@${ver('@lobehub/icons-static-svg')}`],
  'Phosphor Icons': ['phosphor-icons-MIT.txt', `${NM}/@phosphor-icons/core/LICENSE`, `MIT, Copyright (c) 2023 Phosphor Icons, package @phosphor-icons/core@${ver('@phosphor-icons/core')} (fill weight)`],
  Devicon: ['devicon-MIT.txt', `${NM}/devicon/LICENSE`, `MIT, Copyright (c) 2015 konpa, package devicon@${ver('devicon')}`],
  'oh-my-pi repo': ['oh-my-pi-MIT.txt', `${WORK}/lic/omp.txt`, 'MIT, Copyright (c) 2025 Mario Zechner, (c) 2025-2026 Can Bölük'],
  'aider repo': ['aider-Apache-2.0.txt', `${WORK}/lic/aider.txt`, 'Apache-2.0'],
  'jj repo': ['jj-Apache-2.0.txt', `${WORK}/lic/jj.txt`, 'Apache-2.0'],
  original: [null, null, 'CC0-1.0: drawn for Oriel from simple geometric shapes, dedicated to the public domain'],
};
fs.rmSync(path.join(OUT, 'licenses'), { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'licenses'));
const count = {};
for (const c of catalog) count[c.source] = (count[c.source] ?? 0) + 1;
const licLines = Object.keys(count).map((s) => {
  const [file, from, text] = LIC[s];
  if (file) fs.copyFileSync(from, path.join(OUT, 'licenses', file));
  return `- ${s} — ${text}${file ? `. Full text: [licenses/${file}](licenses/${file})` : ''}`;
});
fs.writeFileSync(path.join(OUT, 'SOURCES.md'), `# Program icon sources

Every SVG in \`svg/\` and its source. Counts: ${Object.entries(count).map(([k, v]) => `${k} (${catalog.find((c) => c.source === k).license}): ${v}`).join(', ')}.

Notes:
- One style: a single solid path per icon, \`fill="currentColor"\`, no strokes, no gradients, no text. Each glyph is fitted into a 24x24 viewBox (about 18 units for wide or tall marks, about 16 for square or dense ones) and optically centered. \`tools/build.mjs\` generates everything here; see \`tools/README.md\`.
- Brand marks are trademarks of their owners. The licenses below cover the SVG files, not the trademarks; use marks only to identify the program.
- Matching: \`match.agent\` = herdr agent kind (\`pane.agent\`), \`process\` = the foreground process's name, argv0 basename or script basename (a leading \`-\` of login shells stripped), \`titlePrefix\` = the start of herdr's \`terminal_title_stripped\` up to a space (herdr strips status glyphs such as \`✳\` and spinners), \`scriptSuffix\` = the end of the script path a \`node\`/\`bun\` process runs. A shell or nothing known uses \`terminal\`; an unknown program \`placeholder\` (drawn with its first letter).
- Tiles (one rule): background = brand color (saturation capped at 0.75, darkened a little when white is just short of 3:1), glyph white when it reaches 3:1 on it, else #111111. Near-black or near-white brands use the neutral tile #2b2d31 with a white glyph. Shells and generic tool glyphs use #2b2d31 with the green glyph #7ee787; \`placeholder\` uses a gray glyph. Draw the 24-unit viewBox at 17 pt centered in the 22x18 pt tile.

| id | source | license | original URL | notes |
|---|---|---|---|---|
${rows.join('\n')}

## Licenses

${licLines.join('\n')}
`);

// ---- contact sheet ----------------------------------------------------------------------------------
const glyph = (c) => fs.readFileSync(path.join(OUT, c.svg), 'utf8').match(/ d="([^"]+)"/)[1];
const tile = (c, x, y, s) => `<g transform="translate(${x},${y}) scale(${s})"><rect x="0.25" y="0.25" width="21.5" height="17.5" rx="4.75" fill="${c.tile.background}" stroke="#000" stroke-opacity="0.18" stroke-width="0.5"/>`
  + `<rect x="1" y="0.6" width="20" height="5" rx="3" fill="#fff" opacity="0.06"/>`
  + `<svg x="2.5" y="0.5" width="17" height="17" viewBox="0 0 24 24"><path d="${glyph(c)}" fill="${c.tile.glyph}"/></svg></g>`;
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const COLS = 8, CW = 140, CH = 116, TOP = 170;
const STRIPS = [['#1e1e1e', '#ddd'], ['#f5f5f5', '#222']];
const ROW = ['claude', 'codex', 'zsh', 'neovim', 'git', 'docker', 'python', 'node', 'gemini', 'kilo', 'jj', 'terminal'].map((id) => catalog.find((c) => c.id === id));
let head = '';
STRIPS.forEach(([bg, fg], i) => {
  const y = 30 + i * 66;
  head += `<rect x="0" y="${y}" width="${COLS * CW}" height="62" fill="${bg}"/><text x="12" y="${y + 14}" font-family="Helvetica" font-size="10" fill="${fg}">tab row, 1x and 2x</text>`;
  ROW.forEach((c, j) => { head += tile(c, 12 + j * 26, y + 30, 1) + tile(c, 340 + j * 52, y + 13, 2); });
});
const cells = catalog.map((c, i) => {
  const ox = (i % COLS) * CW, oy = TOP + Math.floor(i / COLS) * CH;
  let s = `<text x="${ox + 8}" y="${oy + 13}" font-family="Helvetica" font-size="11" font-weight="bold" fill="#222">${esc(c.id)}</text>`
    + `<text x="${ox + 8}" y="${oy + 25}" font-family="Helvetica" font-size="9" fill="#666">${esc(c.source)}</text>`;
  STRIPS.forEach(([bg], k) => { const y = oy + 30 + k * 42; s += `<rect x="${ox + 4}" y="${y}" width="${CW - 8}" height="42" fill="${bg}"/>` + tile(c, ox + 14, y + 12, 1) + tile(c, ox + 50, y + 3, 2); });
  return s;
});
const W = COLS * CW, H = TOP + Math.ceil(catalog.length / COLS) * CH;
const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="100%" height="100%" fill="#e8e8e8"/>`
  + `<text x="12" y="19" font-family="Helvetica" font-size="12" font-weight="bold" fill="#222">Oriel program icons. 1 px = 1 pt: each tile at 22x18 (1x) and 44x36 (2x), on dark #1e1e1e and light #f5f5f5.</text>${head}${cells.join('')}</svg>`;
fs.writeFileSync(`${WORK}/sheet.svg`, sheet);
fs.writeFileSync(path.join(OUT, 'contact-sheet.png'), new Resvg(sheet, { font: { loadSystemFonts: true } }).render().asPng());

// ---- verify -----------------------------------------------------------------------------------------
const bad = [];
for (const c of catalog) {
  const s = fs.readFileSync(path.join(OUT, c.svg), 'utf8');
  const fills = [...s.matchAll(/fill="([^"]*)"/g)].map((m) => m[1]);
  if (/stroke|style|<script|<image|<text|gradient|transform|href|<mask|clip/i.test(s) || fills.some((f) => f !== 'currentColor') || !fills.length) bad.push(`${c.id}: attrs`);
  const r = raster(glyph(c), 48);
  if (!(r.ink > 20)) bad.push(`${c.id}: empty`);
  if (contrast(c.tile.background, c.tile.glyph) < 3) bad.push(`${c.id}: contrast ${contrast(c.tile.background, c.tile.glyph).toFixed(2)}`);
}
console.log(catalog.length, 'icons', count);
console.log(fits.join(' '));
if (bad.length) { console.log('CHECK FAILED:\n' + bad.join('\n')); process.exitCode = 1; } else console.log('verify ok');
