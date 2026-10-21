# Program icon sources

Every SVG in `svg/` and its source. Counts: Simple Icons (CC0-1.0): 72, oh-my-pi repo (MIT): 1, Lobe Icons (MIT): 15, original (CC0-1.0): 5, aider repo (Apache-2.0): 1, Lucide (ISC): 10, jj repo (Apache-2.0): 1, Devicon (MIT): 1.

Notes:
- All glyphs use `currentColor` (fill, or stroke for Lucide and original line glyphs) so the app can tint them, except `jj` (full color).
- Brand marks are trademarks of their owners. The licenses below cover the SVG files, not the trademarks; use marks only to identify the program.
- Matching: `match.agent` = herdr agent kind (`pane.agent`), `process` = foreground argv0 basename (strip a leading `-` of login shells), `titlePrefix` = first word of the terminal title, `scriptSuffix` = script path suffix when argv0 is `node`/`bun`. Unmatched panes use `terminal`; `placeholder` is for unknown/loading.
- Tile colors are chosen for Oriel from each brand color; shells and shell utilities use a dark tile (#2b2d31) with a green glyph.

| id | source | license | original URL | notes |
|---|---|---|---|---|
| pi | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/pi.svg |  |
| omp | oh-my-pi repo | MIT | https://github.com/can1357/oh-my-pi/blob/main/packages/collab-web/public/favicon.svg | pi glyph path from the favicon; dark rect and gradient dropped |
| claude | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/claudecode.svg |  |
| codex | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/codex.svg) |  |
| copilot | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/githubcopilot.svg |  |
| devin | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/devin.svg) |  |
| droid | original | CC0-1.0 | — | Factory publishes no permissive logo (Factory-AI/factory has no license); generic robot glyph |
| kimi | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/kimi.svg |  |
| opencode | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/opencode.svg |  |
| kilo | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/kilocode.svg) |  |
| hermes | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/hermesagent.svg) |  |
| qoder | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/qoder.svg) |  |
| qwen | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/qwen.svg |  |
| cursor | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/cursor.svg |  |
| mastra | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/mastra.svg) |  |
| antigravity | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/antigravity.svg) |  |
| grok | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/grok.svg) |  |
| letta | original | CC0-1.0 | — | no logo SVG in letta-ai repos and none in Simple Icons/Lobe; "L" monogram |
| gemini | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/googlegemini.svg |  |
| amp | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/amp.svg) | Simple Icons "amp" is the AMP web project, not Sourcegraph Amp |
| goose | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/goose.svg) |  |
| aider | aider repo | Apache-2.0 | https://github.com/Aider-AI/aider/blob/main/aider/website/assets/icons/safari-pinned-tab.svg | outer square removed so the mark is the glyph (was a knock-out) |
| crush | original | CC0-1.0 | — | charmbracelet/crush is FSL-1.1, no permissive logo; "C" monogram |
| ollama | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/ollama.svg |  |
| cline | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/cline.svg |  |
| kiro | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/kiro.svg) |  |
| maki | original | CC0-1.0 | — | unknown brand; "M" monogram |
| meta | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/meta.svg |  |
| poolside | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/poolside.svg) |  |
| openclaw | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/openclaw.svg) |  |
| mistral | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/mistralai.svg |  |
| terminal | Lucide | ISC | https://lucide.dev/icons/terminal | fallback for any unmatched pane |
| zsh | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/zsh.svg |  |
| bash | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/gnubash.svg |  |
| fish | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/fishshell.svg |  |
| nushell | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nushell.svg |  |
| vim | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vim.svg |  |
| neovim | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/neovim.svg |  |
| helix | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/helix.svg |  |
| emacs | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/gnuemacs.svg |  |
| nano | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nano.svg |  |
| pager | Lucide | ISC | https://lucide.dev/icons/book-open |  |
| bat | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/bat.svg |  |
| git | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/git.svg |  |
| lazygit | Lucide | ISC | https://lucide.dev/icons/git-compare | no lazygit logo SVG; generic git-changes glyph |
| tig | Lucide | ISC | https://lucide.dev/icons/git-commit-horizontal | no tig logo; generic commit glyph |
| github | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/github.svg |  |
| jj | jj repo | Apache-2.0 | https://github.com/jj-vcs/jj/blob/main/docs/images/jj-logo.svg | full-color logo kept (multi-color mark); <use> inlined, style= turned into fill= |
| monitor | Lucide | ISC | https://lucide.dev/icons/activity |  |
| ssh | Lucide | ISC | https://lucide.dev/icons/key-round |  |
| logs | Lucide | ISC | https://lucide.dev/icons/scroll-text |  |
| sleep | original | CC0-1.0 | — | zZ glyph |
| tmux | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/tmux.svg |  |
| yazi | Lucide | ISC | https://lucide.dev/icons/folder-open | no yazi logo SVG; generic file-manager glyph |
| docker | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/docker.svg |  |
| podman | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/podman.svg |  |
| kubernetes | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/kubernetes.svg | k9s has no permissive SVG mark; shares the Kubernetes wheel |
| terraform | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/terraform.svg |  |
| packer | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/packer.svg |  |
| nomad | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nomad.svg |  |
| vagrant | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vagrant.svg |  |
| vault | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vault.svg |  |
| consul | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/consul.svg |  |
| aws | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/aws.svg) |  |
| gcloud | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/googlecloud.svg |  |
| azure | Lobe Icons | MIT | https://github.com/lobehub/lobe-icons (@lobehub/icons-static-svg icons/azure.svg) |  |
| vercel | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vercel.svg |  |
| cloudflare | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/cloudflare.svg |  |
| heroku | Devicon | MIT | https://github.com/devicons/devicon/blob/master/icons/heroku/heroku-plain.svg |  |
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
| make | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/gnu.svg |  |
| npm | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/npm.svg |  |
| pnpm | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/pnpm.svg |  |
| yarn | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/yarn.svg |  |
| vite | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/vite.svg |  |
| postgres | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/postgresql.svg |  |
| sqlite | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/sqlite.svg |  |
| database | Lucide | ISC | https://lucide.dev/icons/database | generic database glyph |
| python | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/python.svg |  |
| uv | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/uv.svg |  |
| jupyter | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/jupyter.svg |  |
| node | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/nodedotjs.svg |  |
| bun | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/bun.svg |  |
| deno | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/deno.svg |  |
| ruby | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/ruby.svg |  |
| go | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/go.svg |  |
| rust | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/rust.svg |  |
| java | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/openjdk.svg |  |
| swift | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/swift.svg |  |
| zig | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/zig.svg |  |
| clang | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/llvm.svg |  |
| dart | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/dart.svg |  |
| flutter | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/flutter.svg |  |
| dotnet | Simple Icons | CC0-1.0 | https://github.com/simple-icons/simple-icons/blob/develop/icons/dotnet.svg |  |
| placeholder | Lucide | ISC | https://lucide.dev/icons/circle-dashed | shown while the program is unknown/loading |

## Licenses

- Simple Icons — CC0-1.0 (public domain dedication): https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md (package simple-icons@16.35.0). Simple Icons asks users to check each brand's guidelines: https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md
- Lobe Icons — MIT, Copyright (c) LobeHub: https://github.com/lobehub/lobe-icons/blob/master/LICENSE (package @lobehub/icons-static-svg@1.97.0).
- Lucide — ISC, Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022: https://github.com/lucide-icons/lucide/blob/main/LICENSE (package lucide-static@1.61.0).
- Devicon — MIT, Copyright (c) 2015 konpa: https://github.com/devicons/devicon/blob/master/LICENSE
- oh-my-pi repo — MIT: https://github.com/can1357/oh-my-pi/blob/main/LICENSE
- aider repo — Apache-2.0: https://github.com/Aider-AI/aider/blob/main/LICENSE.txt
- jj repo — Apache-2.0: https://github.com/jj-vcs/jj/blob/main/LICENSE
- original — drawn for Oriel from simple shapes (24x24), released CC0-1.0.
