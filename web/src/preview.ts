// Preview: an image, a PDF (pdf.js), audio or video (WebKit's player) from the card's file, or the info view. Row 2's
// zoom comes in as `zoom`; a PDF reports its page.
import "pdfjs-dist/web/pdf_viewer.css"
import "./file/preview.css"
import { arg, ask, type In, type PreviewReply, receive, report } from "./lib/bridge"
import { failed, info } from "./lib/info"

type Zoom = Extract<In, { op: "zoom" }>["to"]
let zoom: (to: Zoom) => void = () => {}
/** What the file shown holds: an image's resize observer, a PDF's worker. */
let release = () => {}

const image = (url: string, fallback: () => void) => {
  const box = Object.assign(document.createElement("div"), { className: "scroller" })
  const img = Object.assign(new Image(), { src: url, alt: arg.split("/").pop() ?? "" })
  box.append(img)
  document.body.replaceChildren(box)
  // Fit shrinks a large image to the card, never enlarges a small one.
  let scale: number | "fit" = "fit"
  const fit = () => Math.min(1, box.clientWidth / img.naturalWidth, box.clientHeight / img.naturalHeight)
  const apply = () => {
    img.style.width = `${img.naturalWidth * (scale === "fit" ? fit() : scale)}px`
  }
  img.onload = apply
  img.onerror = fallback
  const observer = new ResizeObserver(apply)
  observer.observe(box)
  release = () => observer.disconnect()
  zoom = (to) => {
    const now = scale === "fit" ? fit() : scale
    scale = to === "fit" ? "fit" : to === "actual" ? 1 : Math.min(16, Math.max(0.05, now * (to === "in" ? 1.25 : 0.8)))
    apply()
  }
}

const pdf = async (data: Uint8Array, fallback: () => void) => {
  const pdfjs = await import("pdfjs-dist")
  pdfjs.GlobalWorkerOptions.workerSrc = "pdf.worker.min.mjs"
  // The viewer reads the library from here.
  Object.assign(globalThis, { pdfjsLib: pdfjs })
  const { EventBus, PDFViewer } = await import("pdfjs-dist/web/pdf_viewer.mjs")
  const container = Object.assign(document.createElement("div"), { className: "pdf" })
  container.append(Object.assign(document.createElement("div"), { className: "pdfViewer" }))
  document.body.replaceChildren(container)
  const eventBus = new EventBus()
  const viewer = new PDFViewer({ container, eventBus })
  const scales: Record<Zoom, string> = { fit: "page-width", actual: "page-actual", in: "", out: "" }
  eventBus.on("pagesinit", () => {
    viewer.currentScaleValue = scales.fit
  })
  eventBus.on("pagechanging", ({ pageNumber }: { pageNumber: number }) =>
    report({ op: "page", page: pageNumber, pages: viewer.pagesCount }),
  )
  // The scheme serves pdf.js's fonts, maps and decoders from the bundle's one folder.
  const task = pdfjs.getDocument({
    data,
    isEvalSupported: false,
    wasmUrl: "./",
    standardFontDataUrl: "./",
    cMapUrl: "./",
  })
  // A failed load would leave its worker running.
  const document_ = await task.promise.catch(() => void task.destroy())
  if (!document_) return fallback()
  viewer.setDocument(document_)
  release = () => void document_.destroy()
  report({ op: "page", page: 1, pages: document_.numPages })
  zoom = (to) => {
    if (to === "in") viewer.increaseScale()
    else if (to === "out") viewer.decreaseScale()
    else viewer.currentScaleValue = scales[to]
  }
}

let url = ""

const show = async (file: PreviewReply) => {
  zoom = () => {}
  release()
  release = () => {}
  URL.revokeObjectURL(url)
  if ("info" in file) return info(file.info, document.body)
  // A file WebKit or pdf.js cannot decode: the info view, never an empty card.
  const fallback = () => {
    zoom = () => {}
    info(file.fallback, document.body)
  }
  const bytes: Uint8Array = (Uint8Array as unknown as { fromBase64(s: string): Uint8Array }).fromBase64(file.data)
  if (file.type === "application/pdf") return pdf(bytes, fallback)
  url = URL.createObjectURL(new Blob([bytes], { type: file.type }))
  if (file.type.startsWith("image/")) return image(url, fallback)
  const player = document.createElement(file.type.startsWith("audio/") ? "audio" : "video")
  Object.assign(player, { src: url, controls: true, className: "player", onerror: fallback })
  document.body.replaceChildren(player)
}

/** One file at a time, in order: a PDF loads over several turns. */
let shown = ask({ op: "read" }).then(show, (error) => failed(error, document.body))
receive((message) => {
  if (message.op === "zoom") zoom(message.to)
  // The file again after a change on disk.
  if (message.op === "load") shown = shown.then(() => show(message as PreviewReply))
})
