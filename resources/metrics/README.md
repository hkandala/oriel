# Metrics dashboard

`dashboard.html` shows how the UI-polish phases went: time, commits, lines, review agents, CI runs, and
which reviews were worth it. It is one self-contained page; open it in a browser.

Re-run after a phase adds `plan/metrics/NN.json`:

```sh
python3 resources/metrics/build.py
```

The script reads every `plan/metrics/*.json`, git (each phase's `base..head`) and GitHub Actions runs
(`gh run list`). It saves the runs to `ci-runs.json`, so without `gh` or a network it builds from that
file.
