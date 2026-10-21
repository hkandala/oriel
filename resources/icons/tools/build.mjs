// Builds /Users/hkandala/code/oriel/resources/icons from permissive icon sets.
import fs from 'node:fs';
import path from 'node:path';
import * as si from 'simple-icons';

const OUT = '/Users/hkandala/code/oriel/resources/icons';
const NM = '/tmp/icons-work/node_modules';
const SHELL_TILE = { background: '#2b2d31', glyph: '#7ee787' };
const STROKE = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';

const SRC = {
  si: { name: 'Simple Icons', license: 'CC0-1.0', url: (s) => `https://github.com/simple-icons/simple-icons/blob/develop/icons/${s}.svg` },
  lobe: { name: 'Lobe Icons', license: 'MIT', url: (s) => `https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/${s}.svg)` },
  lucide: { name: 'Lucide', license: 'ISC', url: (s) => `https://lucide.dev/icons/${s}` },
  devicon: { name: 'Devicon', license: 'MIT', url: (s) => `https://github.com/devicons/devicon/blob/master/icons/${s}` },
  orig: { name: 'original', license: 'CC0-1.0', url: () => '' },
};

// Original glyphs, 24x24, drawn for Oriel.
const ORIG = {
  sleep: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ${STROKE}><path d="M3 11h8l-8 9h8"/><path d="M14 4h7l-7 7h7"/></svg>`,
  droid: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ${STROKE}><rect x="4" y="8" width="16" height="12" rx="3"/><path d="M12 8V5"/><circle cx="12" cy="3.5" r="1.5"/><circle cx="9" cy="14" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="14" r="1.5" fill="currentColor" stroke="none"/></svg>`,
  letta: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ${STROKE}><rect x="3" y="3" width="18" height="18" rx="4"/><path d="M9.5 7.5v9h6"/></svg>`,
  crush: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ${STROKE}><rect x="3" y="3" width="18" height="18" rx="4"/><path d="M15.5 9a4 4 0 1 0 0 6"/></svg>`,
  maki: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ${STROKE}><rect x="3" y="3" width="18" height="18" rx="4"/><path d="M7.5 16.5v-9l4.5 5 4.5-5v9"/></svg>`,
};

// [id, title, kind, src, match, extra]
// src: 'si:slug' | 'lobe:name' | 'lucide:name' | 'devicon:dir/file.svg' | 'orig' | 'file:path|source|license|url'
const E = [
  // agents
  ['pi', 'Pi', 'agent', 'si:pi', { agent: ['pi'], process: ['pi'], titlePrefix: ['π'], scriptSuffix: ['pi-coding-agent/dist/cli.js', 'pi-coding-agent/dist/bundle/cli.js'] }],
  ['omp', 'Oh My Pi', 'agent', 'file:ext/omp-mark.svg|oh-my-pi repo|MIT|https://github.com/can1357/oh-my-pi/blob/main/packages/collab-web/public/favicon.svg', { agent: ['omp'], process: ['omp'] }, { brandColor: '#9b4dff', tile: { background: '#0f0a14', glyph: '#ed4abf' }, notes: 'pi glyph path from the favicon; dark rect and gradient dropped' }],
  ['claude', 'Claude Code', 'agent', 'si:claudecode', { agent: ['claude'], process: ['claude'], titlePrefix: ['✳', 'Claude Code'], scriptSuffix: ['@anthropic-ai/claude-code/cli.js'] }],
  ['codex', 'Codex', 'agent', 'lobe:codex', { agent: ['codex'], process: ['codex'], scriptSuffix: ['@openai/codex/bin/codex.js'] }, { brandColor: '#3941ff', tile: { background: '#f5f5f4', glyph: '#111111' } }],
  ['copilot', 'GitHub Copilot CLI', 'agent', 'si:githubcopilot', { agent: ['copilot'], process: ['copilot'], scriptSuffix: ['copilot/npm-loader.js', '@github/copilot/index.js'] }, { tile: { background: '#f5f5f4', glyph: '#3b50e0' } }],
  ['devin', 'Devin', 'agent', 'lobe:devin', { agent: ['devin'], process: ['devin'] }, { brandColor: '#0294de', tile: { background: '#f5f5f4', glyph: '#111111' } }],
  ['droid', 'Droid (Factory)', 'agent', 'orig', { agent: ['droid'], process: ['droid'] }, { brandColor: '#000000', tile: { background: '#111111', glyph: '#ffffff' }, notes: 'Factory publishes no permissive logo (Factory-AI/factory has no license); generic robot glyph' }],
  ['kimi', 'Kimi Code', 'agent', 'si:kimi', { agent: ['kimi'], process: ['kimi', 'kimi-cli'] }],
  ['opencode', 'OpenCode', 'agent', 'si:opencode', { agent: ['opencode'], process: ['opencode'] }, { tile: { background: '#2f2f2f', glyph: '#f5f5f5' } }],
  ['kilo', 'Kilo Code', 'agent', 'lobe:kilocode', { agent: ['kilo'], process: ['kilo', 'kilocode'] }, { brandColor: '#f8f675', tile: { background: '#1b1b1b', glyph: '#f8f675' } }],
  ['hermes', 'Hermes Agent', 'agent', 'lobe:hermesagent', { agent: ['hermes'], process: ['hermes'] }, { brandColor: '#000000', tile: { background: '#f5f5f4', glyph: '#111111' } }],
  ['qoder', 'Qoder', 'agent', 'lobe:qoder', { agent: ['qodercli'], process: ['qodercli', 'qoder'] }, { brandColor: '#2adb5c', tile: { background: '#111111', glyph: '#2adb5c' } }],
  ['qwen', 'Qwen Code', 'agent', 'si:qwen', { agent: ['qwen'], process: ['qwen'], scriptSuffix: ['@qwen-code/qwen-code/cli.js'] }],
  ['cursor', 'Cursor Agent', 'agent', 'si:cursor', { agent: ['cursor'], process: ['cursor-agent', 'agent'] }],
  ['mastra', 'Mastra Code', 'agent', 'lobe:mastra', { agent: ['mastracode'], process: ['mastracode', 'mastra'] }, { brandColor: '#000000', tile: { background: '#171717', glyph: '#ffffff' } }],
  ['antigravity', 'Google Antigravity', 'agent', 'lobe:antigravity', { agent: ['agy', 'antigravity_cli'], process: ['agy', 'antigravity'] }, { brandColor: '#3186ff', tile: { background: '#f5f5f4', glyph: '#3186ff' } }],
  ['grok', 'Grok', 'agent', 'lobe:grok', { agent: ['grok'], process: ['grok'] }, { brandColor: '#000000', tile: { background: '#000000', glyph: '#ffffff' } }],
  ['letta', 'Letta Code', 'agent', 'orig', { agent: ['letta'], process: ['letta'] }, { brandColor: '#000000', tile: { background: '#f5f5f4', glyph: '#111111' }, notes: 'no logo SVG in letta-ai repos and none in Simple Icons/Lobe; "L" monogram' }],
  ['gemini', 'Gemini CLI', 'agent', 'si:googlegemini', { agent: ['gemini'], process: ['gemini'], scriptSuffix: ['@google/gemini-cli/dist/index.js'] }, { tile: { background: '#f5f5f4', glyph: '#4f7ff0' } }],
  ['amp', 'Amp', 'agent', 'lobe:amp', { agent: ['amp'], process: ['amp'] }, { brandColor: '#f34e3f', notes: 'Simple Icons "amp" is the AMP web project, not Sourcegraph Amp' }],
  ['goose', 'Goose', 'agent', 'lobe:goose', { process: ['goose'] }, { brandColor: '#000000', tile: { background: '#f5f5f4', glyph: '#111111' } }],
  ['aider', 'Aider', 'agent', 'file:ext/aider-mark.svg|aider repo|Apache-2.0|https://github.com/Aider-AI/aider/blob/main/aider/website/assets/icons/safari-pinned-tab.svg', { process: ['aider'] }, { brandColor: '#14b014', tile: { background: '#111111', glyph: '#14b014' }, notes: 'outer square removed so the mark is the glyph (was a knock-out)' }],
  ['crush', 'Crush', 'agent', 'orig', { process: ['crush'] }, { brandColor: '#6b50ff', tile: { background: '#6b50ff', glyph: '#ffffff' }, notes: 'charmbracelet/crush is FSL-1.1, no permissive logo; "C" monogram' }],
  ['ollama', 'Ollama', 'agent', 'si:ollama', { process: ['ollama'] }],
  ['cline', 'Cline', 'agent', 'si:cline', { agent: ['cline'], process: ['cline'] }],
  ['kiro', 'Kiro', 'agent', 'lobe:kiro', { agent: ['kiro'], process: ['kiro-cli', 'kiro'] }, { brandColor: '#9046ff' }],
  ['maki', 'Maki', 'agent', 'orig', { agent: ['maki'], process: ['maki'] }, { brandColor: '#444444', notes: 'unknown brand; "M" monogram' }],
  ['meta', 'Meta (Muse)', 'agent', 'si:meta', { agent: ['muse'], process: ['muse'] }, { tile: { background: '#ffffff', glyph: '#0467df' } }],
  ['poolside', 'Poolside', 'agent', 'lobe:poolside', { process: ['pool', 'poolside'] }, { brandColor: '#4137ff' }],
  ['openclaw', 'OpenClaw', 'agent', 'lobe:openclaw', { process: ['openclaw'] }, { brandColor: '#ff4d4d' }],
  ['mistral', 'Mistral Vibe', 'agent', 'si:mistralai', { process: ['vibe'], titlePrefix: ['Vibe'] }],
  // shells
  ['terminal', 'Shell', 'shell', 'lucide:terminal', { process: ['sh', 'dash', 'ksh', 'tcsh', 'csh', 'login'] }, { notes: 'fallback for any unmatched pane' }],
  ['zsh', 'zsh', 'shell', 'si:zsh', { process: ['zsh', '-zsh'] }],
  ['bash', 'bash', 'shell', 'si:gnubash', { process: ['bash', '-bash'] }],
  ['fish', 'fish', 'shell', 'si:fishshell', { process: ['fish', '-fish'] }],
  ['nushell', 'Nushell', 'shell', 'si:nushell', { process: ['nu'] }],
  // editors
  ['vim', 'Vim', 'editor', 'si:vim', { process: ['vim', 'vi', 'view', 'vimdiff', 'gvim'] }],
  ['neovim', 'Neovim', 'editor', 'si:neovim', { process: ['nvim'] }],
  ['helix', 'Helix', 'editor', 'si:helix', { process: ['hx', 'helix'] }, { tile: { background: '#281733', glyph: '#d4c7ff' } }],
  ['emacs', 'Emacs', 'editor', 'si:gnuemacs', { process: ['emacs', 'emacsclient'] }],
  ['nano', 'nano', 'editor', 'si:nano', { process: ['nano', 'pico'] }],
  ['pager', 'Pager / man', 'tool', 'lucide:book-open', { process: ['less', 'more', 'most', 'man'] }, { shell: true }],
  ['bat', 'bat', 'tool', 'si:bat', { process: ['bat'] }],
  // git
  ['git', 'Git', 'tool', 'si:git', { process: ['git'] }],
  ['lazygit', 'lazygit', 'tool', 'lucide:git-compare', { process: ['lazygit'] }, { brandColor: '#3fb950', tile: { background: '#2f8f46', glyph: '#ffffff' }, notes: 'no lazygit logo SVG; generic git-changes glyph' }],
  ['tig', 'tig', 'tool', 'lucide:git-commit-horizontal', { process: ['tig'] }, { brandColor: '#f03c2e', notes: 'no tig logo; generic commit glyph' }],
  ['github', 'GitHub CLI', 'tool', 'si:github', { process: ['gh'] }, { tile: { background: '#f5f5f4', glyph: '#181717' } }],
  ['jj', 'Jujutsu', 'tool', 'file:ext/jj-flat.svg|jj repo|Apache-2.0|https://github.com/jj-vcs/jj/blob/main/docs/images/jj-logo.svg', { process: ['jj', 'jjui', 'lazyjj'] }, { monochrome: false, brandColor: '#2f9fdf', tile: { background: '#e8f4fb', glyph: '#0e254f' }, notes: 'full-color logo kept (multi-color mark); <use> inlined, style= turned into fill=' }],
  // system
  ['monitor', 'Monitor', 'tool', 'lucide:activity', { process: ['top', 'htop', 'btop', 'btm', 'atop', 'glances', 'gotop', 'nvtop', 'asitop'] }, { shell: true }],
  ['ssh', 'SSH', 'tool', 'lucide:key-round', { process: ['ssh', 'mosh', 'mosh-client', 'et', 'autossh'] }, { shell: true }],
  ['logs', 'Logs', 'tool', 'lucide:scroll-text', { process: ['tail', 'log', 'journalctl', 'lnav'] }, { shell: true }],
  ['sleep', 'Sleep', 'tool', 'orig', { process: ['sleep', 'caffeinate', 'wait'] }, { shell: true, notes: 'zZ glyph' }],
  ['tmux', 'tmux', 'tool', 'si:tmux', { process: ['tmux', 'zellij', 'screen'] }],
  ['yazi', 'Yazi', 'tool', 'lucide:folder-open', { process: ['yazi', 'ranger', 'lf', 'nnn', 'mc'] }, { brandColor: '#e7904a', notes: 'no yazi logo SVG; generic file-manager glyph' }],
  // containers / cloud
  ['docker', 'Docker', 'tool', 'si:docker', { process: ['docker', 'docker-compose', 'lazydocker', 'colima'] }],
  ['podman', 'Podman', 'tool', 'si:podman', { process: ['podman'] }],
  ['kubernetes', 'Kubernetes', 'tool', 'si:kubernetes', { process: ['kubectl', 'kubectx', 'kubens', 'k9s', 'helm', 'minikube', 'kind'] }, { notes: 'k9s has no permissive SVG mark; shares the Kubernetes wheel' }],
  ['terraform', 'Terraform', 'tool', 'si:terraform', { process: ['terraform', 'tofu'] }],
  ['packer', 'Packer', 'tool', 'si:packer', { process: ['packer'] }],
  ['nomad', 'Nomad', 'tool', 'si:nomad', { process: ['nomad'] }],
  ['vagrant', 'Vagrant', 'tool', 'si:vagrant', { process: ['vagrant'] }],
  ['vault', 'Vault', 'tool', 'si:vault', { process: ['vault'] }],
  ['consul', 'Consul', 'tool', 'si:consul', { process: ['consul'] }],
  ['aws', 'AWS CLI', 'tool', 'lobe:aws', { process: ['aws', 'sam', 'cdk'] }, { brandColor: '#ff9900', tile: { background: '#232f3e', glyph: '#ff9900' } }],
  ['gcloud', 'Google Cloud', 'tool', 'si:googlecloud', { process: ['gcloud', 'gsutil', 'bq'] }],
  ['azure', 'Azure CLI', 'tool', 'lobe:azure', { process: ['az'] }, { brandColor: '#0669bc' }],
  ['vercel', 'Vercel', 'tool', 'si:vercel', { process: ['vercel', 'vc'] }, { tile: { background: '#111111', glyph: '#ffffff' } }],
  ['cloudflare', 'Cloudflare', 'tool', 'si:cloudflare', { process: ['wrangler', 'cloudflared'] }],
  ['heroku', 'Heroku', 'tool', 'devicon:heroku/heroku-plain.svg', { process: ['heroku'] }, { brandColor: '#6762a6' }],
  ['railway', 'Railway', 'tool', 'si:railway', { process: ['railway'] }, { tile: { background: '#13111c', glyph: '#ffffff' } }],
  ['render', 'Render', 'tool', 'si:render', { process: ['render'] }, { tile: { background: '#f5f5f4', glyph: '#111111' } }],
  ['modal', 'Modal', 'tool', 'si:modal', { process: ['modal'] }, { tile: { background: '#181818', glyph: '#7fee64' } }],
  ['tailscale', 'Tailscale', 'tool', 'si:tailscale', { process: ['tailscale'] }, { tile: { background: '#242424', glyph: '#ffffff' } }],
  ['stripe', 'Stripe', 'tool', 'si:stripe', { process: ['stripe'] }],
  ['sanity', 'Sanity', 'tool', 'si:sanity', { process: ['sanity'] }, { tile: { background: '#f5f5f4', glyph: '#0d0e12' } }],
  ['buildkite', 'Buildkite', 'tool', 'si:buildkite', { process: ['bk', 'buildkite-agent'] }],
  ['bazel', 'Bazel', 'tool', 'si:bazel', { process: ['bazel', 'bazelisk'] }],
  ['nix', 'Nix', 'tool', 'si:nixos', { process: ['nix', 'nh', 'nom', 'nix-build', 'nix-env', 'nix-shell', 'nix-store', 'darwin-rebuild', 'nixos-rebuild'] }],
  ['homebrew', 'Homebrew', 'tool', 'si:homebrew', { process: ['brew'] }],
  ['huggingface', 'Hugging Face', 'tool', 'si:huggingface', { process: ['huggingface-cli', 'hf'] }],
  ['moon', 'moon', 'tool', 'si:moonrepo', { process: ['moon'] }],
  // build / packages
  ['make', 'GNU make / gcc', 'tool', 'si:gnu', { process: ['make', 'gmake', 'configure', 'libtool', 'gcc', 'g++', 'cpp', 'cc'] }],
  ['npm', 'npm', 'tool', 'si:npm', { process: ['npm', 'npx'] }],
  ['pnpm', 'pnpm', 'tool', 'si:pnpm', { process: ['pnpm', 'pnpx'] }],
  ['yarn', 'Yarn', 'tool', 'si:yarn', { process: ['yarn'] }],
  ['vite', 'Vite', 'tool', 'si:vite', { process: ['vite', 'vitest'] }],
  // databases
  ['postgres', 'PostgreSQL', 'tool', 'si:postgresql', { process: ['psql', 'postgres', 'pgcli', 'pg_dump', 'pg_restore'] }],
  ['sqlite', 'SQLite', 'tool', 'si:sqlite', { process: ['sqlite3', 'sqlite', 'litecli'] }, { tile: { background: '#0f80cc', glyph: '#ffffff' } }],
  ['database', 'Database', 'tool', 'lucide:database', { process: ['mysql', 'mariadb', 'mycli', 'redis-cli', 'mongosh', 'mongo', 'duckdb', 'clickhouse', 'usql'] }, { brandColor: '#336791', notes: 'generic database glyph' }],
  // languages
  ['python', 'Python', 'language', 'si:python', { process: ['python', 'python2', 'python2.7', 'python3', 'python3.10', 'python3.11', 'python3.12', 'python3.13', 'python3.14', 'python3.15', 'ipython', 'pip', 'pip3'] }],
  ['uv', 'uv', 'language', 'si:uv', { process: ['uv', 'uvx'] }],
  ['jupyter', 'Jupyter', 'language', 'si:jupyter', { process: ['jupyter', 'jupyter-notebook', 'jupyter-lab', 'jupyter-console', 'jupyter-qtconsole'] }],
  ['node', 'Node.js', 'language', 'si:nodedotjs', { process: ['node'] }],
  ['bun', 'Bun', 'language', 'si:bun', { process: ['bun', 'bunx'] }, { tile: { background: '#f9f0e1', glyph: '#14151a' } }],
  ['deno', 'Deno', 'language', 'si:deno', { process: ['deno'] }],
  ['ruby', 'Ruby', 'language', 'si:ruby', { process: ['ruby', 'irb', 'bundle', 'bundler', 'rails', 'rake', 'gem'] }],
  ['go', 'Go', 'language', 'si:go', { process: ['go', 'gopls', 'dlv'] }],
  ['rust', 'Rust', 'language', 'si:rust', { process: ['cargo', 'rustc', 'rustup', 'bacon'] }],
  ['java', 'Java', 'language', 'si:openjdk', { process: ['java', 'javac', 'jshell', 'gradle', 'mvn'] }],
  ['swift', 'Swift', 'language', 'si:swift', { process: ['swift', 'swiftc', 'xcodebuild', 'xcrun'] }],
  ['zig', 'Zig', 'language', 'si:zig', { process: ['zig'] }],
  ['clang', 'Clang / LLVM', 'language', 'si:llvm', { process: ['clang', 'clang++', 'clang-cpp', 'clang-cl', 'lldb', 'clangd'] }],
  ['dart', 'Dart', 'language', 'si:dart', { process: ['dart', 'pub'] }],
  ['flutter', 'Flutter', 'language', 'si:flutter', { process: ['flutter'] }],
  ['dotnet', '.NET', 'language', 'si:dotnet', { process: ['dotnet'] }],
  // generic
  ['placeholder', 'Placeholder', 'generic', 'lucide:circle-dashed', {}, { brandColor: '#8b8d91', tile: { background: '#3a3c41', glyph: '#8b8d91' }, notes: 'shown while the program is unknown/loading' }],
];

const strip = (s) => s
  .replace(/<\?xml[^>]*>/g, '').replace(/<!DOCTYPE[^>]*>/gs, '').replace(/<!--.*?-->/gs, '')
  .replace(/<title>.*?<\/title>/gs, '').replace(/<metadata>.*?<\/metadata>/gs, '');

function normalize(raw, mode) {
  const s = strip(raw);
  const open = s.match(/<svg\b[^>]*>/s)[0];
  let inner = s.slice(s.indexOf(open) + open.length, s.lastIndexOf('</svg>')).trim();
  const vb = open.match(/viewBox="([^"]+)"/)?.[1]
    ?? `0 0 ${parseFloat(open.match(/width="([\d.]+)/)[1])} ${parseFloat(open.match(/height="([\d.]+)/)[1])}`;
  if (mode === 'color') return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}">${inner}</svg>\n`;
  inner = inner.replace(/(fill|stroke)="#[0-9a-fA-F]{3,8}"/g, '$1="currentColor"').replace(/\s+/g, ' ')
    // drop Lobe's full-box clips and alpha-fade masks: plain shapes tint and render everywhere
    .replace(/<mask\b.*?<\/mask>/g, '').replace(/ (mask|clip-path)="url\([^)]*\)"/g, '');
  if (!inner.includes('url(#')) inner = inner.replace(/<defs>.*?<\/defs>/g, '');
  const attrs = mode === 'stroke' ? STROKE : `fill="currentColor"${/fill-rule="evenodd"/.test(open) ? ' fill-rule="evenodd"' : ''}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}" ${attrs}>${inner}</svg>\n`;
}

const lum = (hex) => {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
};
const defaultTile = (hex) => {
  if (lum(hex) < 0.02) return { background: '#f5f5f4', glyph: '#111111' }; // black marks read best on a light tile
  return { background: hex, glyph: 1.05 / (lum(hex) + 0.05) >= 2.6 ? '#ffffff' : '#111111' };
};

fs.rmSync(path.join(OUT, 'svg'), { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'svg'), { recursive: true });

const catalog = [];
const rows = [];
for (const [id, title, kind, src, match, x = {}] of E) {
  const [type, arg] = src.split(/:(.*)/s);
  let raw, mode = 'fill', source, license, url, brandColor = x.brandColor;
  if (type === 'si') {
    const icon = Object.values(si).find((i) => i?.slug === arg);
    raw = icon.svg; brandColor ??= '#' + icon.hex;
    ({ name: source, license } = SRC.si); url = SRC.si.url(arg);
  } else if (type === 'lobe') {
    raw = fs.readFileSync(`${NM}/@lobehub/icons-static-svg/icons/${arg}.svg`, 'utf8');
    ({ name: source, license } = SRC.lobe); url = SRC.lobe.url(arg);
  } else if (type === 'lucide') {
    raw = fs.readFileSync(`${NM}/lucide-static/icons/${arg}.svg`, 'utf8'); mode = 'stroke';
    ({ name: source, license } = SRC.lucide); url = SRC.lucide.url(arg);
  } else if (type === 'devicon') {
    raw = fs.readFileSync(`${NM}/devicon/icons/${arg}`, 'utf8');
    ({ name: source, license } = SRC.devicon); url = SRC.devicon.url(arg);
  } else if (type === 'orig') {
    raw = ORIG[id]; mode = 'keep';
    ({ name: source, license } = SRC.orig); url = '';
  } else if (type === 'file') {
    const [file, s, l, u] = arg.split('|');
    raw = fs.readFileSync(`/tmp/icons-work/${file}`, 'utf8'); source = s; license = l; url = u;
  }
  if (x.monochrome === false) mode = 'color';
  const svg = mode === 'keep' ? raw + '\n' : normalize(raw, mode);
  fs.writeFileSync(path.join(OUT, 'svg', `${id}.svg`), svg);
  brandColor = (brandColor ?? '#2b2d31').toLowerCase();
  const tile = x.tile ?? (kind === 'shell' || x.shell ? SHELL_TILE : defaultTile(brandColor));
  const m = {};
  for (const k of ['agent', 'process', 'titlePrefix', 'scriptSuffix']) if (match[k]?.length) m[k] = match[k];
  catalog.push({ id, title, kind, match: m, svg: `svg/${id}.svg`, monochrome: mode !== 'color', brandColor, tile, source, license, url });
  rows.push(`| ${id} | ${source} | ${license} | ${url || '—'} | ${x.notes ?? ''} |`);
}
fs.writeFileSync(path.join(OUT, 'catalog.json'), JSON.stringify(catalog, null, 2) + '\n');

const count = {};
for (const c of catalog) count[`${c.source} (${c.license})`] = (count[`${c.source} (${c.license})`] ?? 0) + 1;
fs.writeFileSync(path.join(OUT, 'SOURCES.md'), `# Program icon sources

Every SVG in \`svg/\` and its source. Counts: ${Object.entries(count).map(([k, v]) => `${k}: ${v}`).join(', ')}.

Notes:
- All glyphs use \`currentColor\` (fill, or stroke for Lucide and original line glyphs) so the app can tint them, except \`jj\` (full color).
- Brand marks are trademarks of their owners. The licenses below cover the SVG files, not the trademarks; use marks only to identify the program.
- Matching: \`match.agent\` = herdr agent kind (\`pane.agent\`), \`process\` = foreground argv0 basename (strip a leading \`-\` of login shells), \`titlePrefix\` = first word of the terminal title, \`scriptSuffix\` = script path suffix when argv0 is \`node\`/\`bun\`. Unmatched panes use \`terminal\`; \`placeholder\` is for unknown/loading.
- Tile colors are chosen for Oriel from each brand color; shells and shell utilities use a dark tile (#2b2d31) with a green glyph.

| id | source | license | original URL | notes |
|---|---|---|---|---|
${rows.join('\n')}

## Licenses

- Simple Icons — CC0-1.0 (public domain dedication): https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md (package simple-icons@${JSON.parse(fs.readFileSync(`${NM}/simple-icons/package.json`)).version}). Simple Icons asks users to check each brand's guidelines: https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md
- Lobe Icons — MIT, Copyright (c) LobeHub: https://github.com/lobehub/lobe-icons/blob/master/LICENSE (package @lobehub/icons-static-svg@${JSON.parse(fs.readFileSync(`${NM}/@lobehub/icons-static-svg/package.json`)).version}).
- Lucide — ISC, Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022: https://github.com/lucide-icons/lucide/blob/main/LICENSE (package lucide-static@${JSON.parse(fs.readFileSync(`${NM}/lucide-static/package.json`)).version}).
- Devicon — MIT, Copyright (c) 2015 konpa: https://github.com/devicons/devicon/blob/master/LICENSE
- oh-my-pi repo — MIT: https://github.com/can1357/oh-my-pi/blob/main/LICENSE
- aider repo — Apache-2.0: https://github.com/Aider-AI/aider/blob/main/LICENSE.txt
- jj repo — Apache-2.0: https://github.com/jj-vcs/jj/blob/main/LICENSE
- original — drawn for Oriel from simple shapes (24x24), released CC0-1.0.
`);

// contact sheet: each tile at 1x (22x18), 2x (44x36) and 4x (88x72), glyph 14pt in an r=5pt tile.
const COLS = 6, CW = 230, CH = 120;
const cells = catalog.map((c, i) => {
  const svg = fs.readFileSync(path.join(OUT, c.svg), 'utf8');
  const vb = svg.match(/viewBox="([^"]+)"/)[1];
  const body = svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
  const attrs = svg.match(/^<svg([^>]*)>/)[1].replace(/xmlns="[^"]*"|viewBox="[^"]*"/g, '');
  const ox = (i % COLS) * CW + 12, oy = Math.floor(i / COLS) * CH + 12;
  const tile = (x, y, s) => `<g transform="translate(${x},${y}) scale(${s})"><rect width="22" height="18" rx="5" fill="${c.tile.background}"/>`
    + `<svg x="4" y="2" width="14" height="14" viewBox="${vb}" color="${c.tile.glyph}" ${attrs}>${body}</svg></g>`;
  const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  return tile(ox, oy + 27, 1) + tile(ox + 30, oy + 18, 2) + tile(ox + 82, oy, 4)
    + `<text x="${ox}" y="${oy + 90}" font-family="Helvetica" font-size="13" font-weight="bold" fill="#222">${esc(c.id)}</text>`
    + `<text x="${ox}" y="${oy + 106}" font-family="Helvetica" font-size="10" fill="#666">${esc(c.kind)} · ${esc(c.source)}</text>`;
});
const W = COLS * CW, H = Math.ceil(catalog.length / COLS) * CH + 12;
const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="100%" height="100%" fill="#ececec"/>${cells.join('')}</svg>`;
fs.writeFileSync('/tmp/icons-work/sheet.svg', sheet);
const { Resvg } = await import('@resvg/resvg-js');
fs.writeFileSync(path.join(OUT, 'contact-sheet.png'), new Resvg(sheet, { fitTo: { mode: 'zoom', value: 2 }, font: { loadSystemFonts: true } }).render().asPng());
console.log(catalog.length, 'icons', count);
