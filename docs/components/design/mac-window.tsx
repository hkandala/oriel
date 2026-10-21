'use client';
import { type ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import {
  AgentChat,
  DiffBody,
  HistBody,
  Ico,
  Pane,
  Seg,
  T,
  Term,
  Web,
  type Icon,
} from './panes';

type Leaf = {
  kind: 'term' | 'web' | 'chat' | 'diff' | 'hist';
  title: string;
  icon: Icon;
  body?: string;
  w?: number;
  dim?: boolean;
};
type Split = { dir: 'row' | 'col'; kids: Node[]; w?: number };
type Node = Leaf | Split;
type St = 'w' | 'b' | 'd'; // ◔ working · ▲ needs you · ✓ finished
type Tab = { label: string; icon: Icon; badge?: St; layout: Node };
type Host = { name: string; ws: string[]; tabs: Tab[] };

const GLYPH: Record<St, string> = { w: '◔', b: '▲', d: '✓' };
const p = (kind: Leaf['kind'], title: string, icon: Icon, o: Partial<Leaf> = {}): Leaf => ({ kind, title, icon, ...o });
const CL: Icon = ['claude', '✳'], SH: Icon = ['sh', '>_'], PI: Icon = ['pi', 'π'], WEB: Icon = ['web', '◍'];
const CX: Icon = ['codex', '>_'], DF: Icon = ['codex', '±'], GH: Icon = ['codex', '⑂'];

// One pane lives in one tab. The sidebar rows, status area and the pills demo tell the same story:
// claude works, pi finished (not seen), codex needs you.
const HOSTS: Host[] = [
  {
    name: 'This Mac',
    ws: ['api-server', 'web-app', 'infra'],
    tabs: [
      { label: 'fix-auth', icon: CL, badge: 'w', layout: { dir: 'row', kids: [p('term', 'claude · fix-auth', CL, { body: T.claude, w: 1.4 }), { dir: 'col', kids: [p('term', 'zsh', SH, { body: T.zsh, dim: true }), p('term', 'logs', SH, { body: T.logs, dim: true })] }] } },
      { label: 'docs', icon: PI, badge: 'd', layout: p('chat', 'pi · docs', PI) },
      { label: 'preview', icon: WEB, layout: p('web', 'Dashboard · localhost:3000', WEB) },
      { label: 'diff', icon: DF, layout: { dir: 'row', kids: [p('diff', 'Diff · base=main', DF, { w: 1.5 }), p('term', 'npm test', SH, { body: T.zsh, dim: true })] } },
      { label: 'history', icon: GH, layout: p('hist', 'Git history · main', GH) },
    ],
  },
  {
    name: 'devbox',
    ws: ['infra', 'ml-pipeline'],
    tabs: [
      { label: 'terraform', icon: CX, badge: 'b', layout: { dir: 'row', kids: [p('term', 'codex · migrate', CX, { body: T.codex, w: 1.3 }), p('term', 'zsh', SH, { body: T.zsh, dim: true })] } },
      { label: 'staging', icon: WEB, layout: p('web', 'staging.internal', WEB) },
    ],
  },
  {
    name: 'gpu-01',
    ws: ['training'],
    tabs: [
      { label: 'train', icon: SH, layout: { dir: 'col', kids: [p('term', 'train.py', SH, { body: T.train }), p('term', 'nvidia-smi', SH, { body: T.gpu, dim: true })] } },
      { label: 'eval', icon: CL, layout: p('term', 'claude · eval', CL, { body: T.claude }) },
    ],
  },
];

function Ctl({ n }: { n: Leaf }) {
  const plugin = n.kind === 'diff' || n.kind === 'hist';
  return (
    <>
      {plugin ? (
        <Seg a="plugin" b="term" on={0} />
      ) : n.kind === 'web' ? (
        '‹ ↻ ↗'
      ) : (
        <Seg a="chat" b="term" on={n.kind === 'chat' ? 0 : 1} />
      )}{' '}
      ⤢ ✕
    </>
  );
}

function RenderNode({ n }: { n: Node }) {
  if ('dir' in n)
    return (
      <div className="col" style={{ flex: n.w ?? 1, flexDirection: n.dir === 'row' ? 'row' : 'column' }}>
        {n.kids.map((k, i) => (
          <RenderNode key={i} n={k} />
        ))}
      </div>
    );
  return (
    <Pane icon={n.icon} title={n.title} ctl={<Ctl n={n} />} dim={n.dim} style={{ flex: n.w ?? 1 }}>
      {n.kind === 'term' && <Term body={n.body!} />}
      {n.kind === 'web' && <Web title={n.title.includes('staging') ? 'Staging' : 'Dashboard'} />}
      {n.kind === 'chat' && <AgentChat agent={n.icon[0] === 'pi' ? 'pi' : 'claude'} />}
      {n.kind === 'diff' && <DiffBody />}
      {n.kind === 'hist' && <HistBody />}
    </Pane>
  );
}

const tryIt = (
  <>
    <b>Try:</b>{" "}scroll the main area sideways (trackpad or shift+wheel): the row of every tab whose page is visible
    lights up. Scroll the sidebar sideways, or click the dots, to switch machines. The <b>diff</b> and{' '}
    <b>history</b> tabs are plugin panes. The tab bar, shown while the sidebar is hidden, is in the{' '}
    <a href="/overview/index.html#f-window">overview</a>.
  </>
);

/** The interactive macOS window: machine pages, lit tab rows and the strip. */
export function MacWindow({ caption = tryIt }: { caption?: ReactNode }) {
  const [host, setHost] = useState(0);
  const pager = useRef<HTMLDivElement>(null);
  const strip = useRef<HTMLDivElement>(null);
  const h = HOSTS[host];

  // Light the row of every tab whose page is visible.
  const update = useCallback(() => {
    const s = strip.current, page = pager.current?.children[host];
    if (!s || !page) return;
    const w = s.clientWidth || 1, x = s.scrollLeft, a = Math.floor(x / w);
    page.querySelectorAll('.trow').forEach((t, i) => t.classList.toggle('lit', i >= a && (i === a || x + w - i * w > 2)));
  }, [host]);

  useEffect(() => {
    if (strip.current) strip.current.scrollLeft = 0;
    update();
  }, [update]);

  // Switch machine once the sidebar pager settles.
  useEffect(() => {
    const el = pager.current;
    if (!el) return;
    let t: ReturnType<typeof setTimeout>;
    const on = () => {
      clearTimeout(t);
      t = setTimeout(() => setHost(Math.round(el.scrollLeft / el.clientWidth)), 120);
    };
    el.addEventListener('scroll', on, { passive: true });
    return () => el.removeEventListener('scroll', on);
  }, []);

  return (
    <figure className="oriel not-prose">
      <div className="win">
        <aside className="side">
          <div className="lights">
            <i />
            <i />
            <i />
          </div>
          <div className="hostpager" ref={pager}>
            {HOSTS.map((hh) => (
              <div className="hostpage" key={hh.name}>
                <div className="hostname">{hh.name}</div>
                {hh.ws.map((w, wi) => (
                  <div key={w}>
                    <div className="ws">{w}</div>
                    {wi === 0 &&
                      hh.tabs.map((t, i) => (
                        <div
                          className="trow"
                          key={t.label}
                          onClick={() => strip.current?.scrollTo({ left: i * strip.current.clientWidth, behavior: 'smooth' })}
                        >
                          <Ico icon={t.icon} />
                          {t.label}
                          {t.badge && <span className={`st ${t.badge}`}>{GLYPH[t.badge]}</span>}
                        </div>
                      ))}
                  </div>
                ))}
              </div>
            ))}
          </div>
          <div className="dots">
            {HOSTS.map((hh, i) => (
              <b
                key={hh.name}
                className={i === host ? 'on' : ''}
                title={hh.name}
                onClick={() => pager.current?.scrollTo({ left: i * pager.current.clientWidth, behavior: 'smooth' })}
              />
            ))}
          </div>
          <div className="status">
            <div className="sum">1 working · 1 needs you · 1 finished</div>
            <div><span className="st b">▲</span> codex needs you · devbox/infra</div>
            <div><span className="st d">✓</span> pi finished · This Mac/api-server</div>
          </div>
          <div className="sfoot">
            <span>⌕ Filter</span>
            <span title="New Workspace">⊞</span>
            <span title="Add Machine…">◍</span>
          </div>
        </aside>
        <div className="main">
          <div className="strip" ref={strip} onScroll={update}>
            {h.tabs.map((t) => (
              <div className="tpage" key={h.name + t.label}>
                <RenderNode n={'dir' in t.layout ? t.layout : { ...t.layout, w: 1 }} />
              </div>
            ))}
          </div>
        </div>
      </div>
      {caption && <figcaption className="cap">{caption}</figcaption>}
    </figure>
  );
}
