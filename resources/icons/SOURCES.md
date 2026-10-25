# Program icon sources

Every SVG in `svg/` and its source. Counts: Simple Icons (CC0-1.0): 63, oh-my-pi repo (MIT): 1, Lobe Icons (MIT): 14, Phosphor Icons (MIT): 16, original (CC0-1.0): 8, aider repo (Apache-2.0): 1, jj repo (Apache-2.0): 1, Devicon (MIT): 1.

Notes:
- One style: a single solid path per icon, `fill="currentColor"`, no strokes, no gradients, no text. Each glyph is fitted into a 24x24 viewBox (about 18 units for wide or tall marks, about 16 for square or dense ones) and optically centered. `tools/build.mjs` generates everything here; see `tools/README.md`.
- Brand marks are trademarks of their owners. The licenses below cover the SVG files, not the trademarks; use marks only to identify the program.
- Matching: `match.agent` = herdr agent kind (`pane.agent`), `process` = the foreground process's name, argv0 basename or script basename (a leading `-` of login shells stripped), `titlePrefix` = the start of herdr's `terminal_title_stripped` up to a space (herdr strips status glyphs such as `✳` and spinners), `scriptSuffix` = the end of the script path a `node`/`bun` process runs. A shell or nothing known uses `terminal`; an unknown program `placeholder` (drawn with its first letter).
- Tiles (one rule): background = brand color (saturation capped at 0.75, darkened a little when white is just short of 3:1), glyph white when it reaches 3:1 on it, else #111111. Near-black or near-white brands use the neutral tile #2b2d31 with a white glyph. Shells and generic tool glyphs use #2b2d31 with the green glyph #7ee787; `placeholder` uses a gray glyph. Draw the 24-unit viewBox at 17 pt centered in the 22x18 pt tile.

| id | source | license | original URL | notes |
|---|---|---|---|---|
| pi | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/pi.svg |  |
| omp | oh-my-pi repo | MIT | https://github.com/can1357/oh-my-pi/blob/main/packages/collab-web/public/favicon.svg | pi glyph path from the favicon; dark rect and gradient dropped |
| claude | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/claudecode.svg |  |
| codex | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/codex.svg) |  |
| copilot | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/githubcopilot.svg |  |
| devin | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/devin.svg) |  |
| droid | Phosphor Icons | MIT | https://phosphoricons.com/?q=robot (@phosphor-icons/core assets/fill/robot-fill.svg) | Factory publishes no permissive logo (Factory-AI/factory has no license); generic robot glyph |
| kimi | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/kimi.svg |  |
| opencode | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/opencode.svg |  |
| kilo | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/kilocode.svg) |  |
| hermes | original | CC0-1.0 | — | the Lobe mark is a detailed portrait that reads as a blob at tab size; solid "H" monogram |
| qoder | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/qoder.svg) |  |
| qwen | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/qwen.svg |  |
| cursor | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/cursor.svg |  |
| mastra | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/mastra.svg) |  |
| antigravity | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/antigravity.svg) |  |
| grok | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/grok.svg) |  |
| letta | original | CC0-1.0 | — | no logo SVG in letta-ai repos and none in Simple Icons/Lobe; solid "L" monogram |
| gemini | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/googlegemini.svg |  |
| amp | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/amp.svg) | Simple Icons "amp" is the AMP web project, not Sourcegraph Amp |
| goose | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/goose.svg) |  |
| aider | aider repo | Apache-2.0 | https://github.com/Aider-AI/aider/blob/main/aider/website/assets/icons/safari-pinned-tab.svg | outer square removed so the mark is the glyph (was a knock-out) |
| crush | original | CC0-1.0 | — | charmbracelet/crush is FSL-1.1, no permissive logo; solid "C" monogram |
| ollama | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/ollama.svg |  |
| cline | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/cline.svg |  |
| kiro | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/kiro.svg) |  |
| maki | original | CC0-1.0 | — | unknown brand; solid "M" monogram |
| poolside | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/poolside.svg) |  |
| openclaw | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/openclaw.svg) |  |
| mistral | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/mistralai.svg |  |
| terminal | Phosphor Icons | MIT | https://phosphoricons.com/?q=terminal-window (@phosphor-icons/core assets/fill/terminal-window-fill.svg) | fallback for any unmatched pane |
| zsh | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/zsh.svg |  |
| bash | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/gnubash.svg |  |
| fish | Phosphor Icons | MIT | https://phosphoricons.com/?q=fish-simple (@phosphor-icons/core assets/fill/fish-simple-fill.svg) | the fish shell mark is thin lines that vanish at 1x; generic fish glyph |
| nushell | original | CC0-1.0 | — | the Nushell mark is the "nu>" wordmark; solid "nu" monogram |
| vim | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vim.svg |  |
| neovim | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/neovim.svg |  |
| helix | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/helix.svg |  |
| emacs | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/gnuemacs.svg |  |
| nano | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nano.svg |  |
| pager | Phosphor Icons | MIT | https://phosphoricons.com/?q=book-open (@phosphor-icons/core assets/fill/book-open-fill.svg) |  |
| bat | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/bat.svg |  |
| git | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/git.svg |  |
| lazygit | Phosphor Icons | MIT | https://phosphoricons.com/?q=git-diff (@phosphor-icons/core assets/fill/git-diff-fill.svg) | no lazygit logo SVG; generic git-changes glyph |
| tig | Phosphor Icons | MIT | https://phosphoricons.com/?q=git-commit (@phosphor-icons/core assets/fill/git-commit-fill.svg) | no tig logo; generic commit glyph |
| github | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/github.svg |  |
| jj | jj repo | Apache-2.0 | https://github.com/jj-vcs/jj/blob/main/docs/images/jj-logo.svg | full-color logo turned into one silhouette: all colors filled, the light parts cut out |
| monitor | Phosphor Icons | MIT | https://phosphoricons.com/?q=gauge (@phosphor-icons/core assets/fill/gauge-fill.svg) |  |
| ssh | Phosphor Icons | MIT | https://phosphoricons.com/?q=key (@phosphor-icons/core assets/fill/key-fill.svg) |  |
| logs | Phosphor Icons | MIT | https://phosphoricons.com/?q=scroll (@phosphor-icons/core assets/fill/scroll-fill.svg) |  |
| sleep | original | CC0-1.0 | — | solid zZ glyph (Phosphor has none) |
| tmux | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/tmux.svg |  |
| yazi | Phosphor Icons | MIT | https://phosphoricons.com/?q=folder-open (@phosphor-icons/core assets/fill/folder-open-fill.svg) | no yazi logo SVG; generic file-manager glyph |
| docker | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/docker.svg |  |
| podman | Phosphor Icons | MIT | https://phosphoricons.com/?q=package (@phosphor-icons/core assets/fill/package-fill.svg) | the Podman seal is fine detail that reads as a blob at 1x; generic container glyph |
| kubernetes | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/kubernetes.svg | k9s has no permissive SVG mark; shares the Kubernetes wheel |
| terraform | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/terraform.svg |  |
| packer | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/packer.svg |  |
| nomad | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nomad.svg |  |
| vagrant | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vagrant.svg |  |
| vault | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vault.svg |  |
| consul | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/consul.svg |  |
| aws | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/aws.svg) | "aws" letters dropped; the smile arrow alone, thickened for 1x |
| gcloud | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/googlecloud.svg |  |
| azure | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/azure.svg) |  |
| vercel | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vercel.svg |  |
| cloudflare | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/cloudflare.svg |  |
| heroku | Devicon | MIT | https://github.com/devicons/devicon/blob/master/icons/heroku/heroku-plain.svg | not in Simple Icons or Lobe |
| railway | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/railway.svg |  |
| render | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/render.svg |  |
| modal | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/modal.svg |  |
| tailscale | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/tailscale.svg |  |
| stripe | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/stripe.svg |  |
| sanity | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/sanity.svg |  |
| buildkite | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/buildkite.svg |  |
| bazel | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/bazel.svg |  |
| nix | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nixos.svg |  |
| homebrew | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/homebrew.svg |  |
| huggingface | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/huggingface.svg |  |
| moon | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/moonrepo.svg |  |
| make | Phosphor Icons | MIT | https://phosphoricons.com/?q=hammer (@phosphor-icons/core assets/fill/hammer-fill.svg) | the GNU head is detailed art that reads as a blob at tab size; generic build glyph |
| npm | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/npm.svg |  |
| pnpm | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/pnpm.svg |  |
| yarn | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/yarn.svg |  |
| vite | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vite.svg |  |
| postgres | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/postgresql.svg | thickened: its thin outlines vanish at 1x |
| sqlite | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/sqlite.svg |  |
| database | Phosphor Icons | MIT | https://phosphoricons.com/?q=database (@phosphor-icons/core assets/fill/database-fill.svg) | generic database glyph |
| python | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/python.svg |  |
| uv | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/uv.svg |  |
| jupyter | Phosphor Icons | MIT | https://phosphoricons.com/?q=planet (@phosphor-icons/core assets/fill/planet-fill.svg) | the Jupyter orbits are thin at 1x; generic planet glyph |
| node | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nodedotjs.svg |  |
| bun | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/bun.svg |  |
| deno | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/deno.svg |  |
| ruby | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/ruby.svg |  |
| go | original | CC0-1.0 | — | Simple Icons "go" is the GO wordmark; solid "G" monogram |
| rust | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/rust.svg |  |
| java | Phosphor Icons | MIT | https://phosphoricons.com/?q=coffee (@phosphor-icons/core assets/fill/coffee-fill.svg) | the OpenJDK mark is thin at 1x; generic coffee cup in Java orange |
| swift | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/swift.svg |  |
| zig | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/zig.svg |  |
| clang | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/llvm.svg |  |
| dart | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/dart.svg |  |
| flutter | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/flutter.svg |  |
| dotnet | original | CC0-1.0 | — | Simple Icons "dotnet" is the .NET wordmark; solid "N" monogram |
| placeholder | Phosphor Icons | MIT | https://phosphoricons.com/?q=circle-dashed (@phosphor-icons/core assets/fill/circle-dashed-fill.svg) | shown while the program is unknown/loading; gray glyph |

## Licenses

- Simple Icons — CC0-1.0, package simple-icons@16.35.0. Simple Icons asks users to check each brand's guidelines: https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md. Full text: [licenses/simple-icons-CC0-1.0.md](licenses/simple-icons-CC0-1.0.md)
- oh-my-pi repo — MIT, Copyright (c) 2025 Mario Zechner, (c) 2025-2026 Can Bölük. Full text: [licenses/oh-my-pi-MIT.txt](licenses/oh-my-pi-MIT.txt)
- Lobe Icons — MIT, Copyright (c) 2023 LobeHub, package @lobehub/icons-static-svg@1.97.0. Full text: [licenses/lobe-icons-MIT.txt](licenses/lobe-icons-MIT.txt)
- Phosphor Icons — MIT, Copyright (c) 2023 Phosphor Icons, package @phosphor-icons/core@2.1.1 (fill weight). Full text: [licenses/phosphor-icons-MIT.txt](licenses/phosphor-icons-MIT.txt)
- original — CC0-1.0: drawn for Oriel from simple geometric shapes, dedicated to the public domain
- aider repo — Apache-2.0. Full text: [licenses/aider-Apache-2.0.txt](licenses/aider-Apache-2.0.txt)
- jj repo — Apache-2.0. Full text: [licenses/jj-Apache-2.0.txt](licenses/jj-Apache-2.0.txt)
- Devicon — MIT, Copyright (c) 2015 konpa, package devicon@2.17.0. Full text: [licenses/devicon-MIT.txt](licenses/devicon-MIT.txt)
