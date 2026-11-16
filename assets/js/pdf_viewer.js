// The handout viewer (docs/MATERIALS.md, Jose 2026-11-15): draws a PDF's
// pages itself, because phones can't show a PDF inside a page reliably
// (iPhones show only the first page; Android browsers offer a download).
//
// PDF.js is loaded the first time a handout is opened, as a module from
// /assets/pdfjs/ (assets/scripts/copy-pdfjs.mjs). The element carries
// data-src, the file's address; its pages go in [data-pdf-pages], which the
// page never redraws (phx-update="ignore"). Escape closes the viewer.

const LOADER = "/assets/pdfjs/load.mjs";
let loading = null;

function loadPdfjs() {
  if (window.ccPdfjs) return Promise.resolve(window.ccPdfjs);
  if (loading) return loading;

  loading = new Promise((resolve, reject) => {
    window.addEventListener("cc:pdfjs-ready", () => resolve(window.ccPdfjs), {
      once: true,
    });
    const script = document.createElement("script");
    script.type = "module";
    script.src = LOADER;
    script.onerror = () => {
      loading = null;
      reject(new Error("PDF.js didn't load"));
    };
    document.head.appendChild(script);
  });

  return loading;
}

export const PdfViewer = {
  mounted() {
    this.pages = this.el.querySelector("[data-pdf-pages]");
    this.status = this.el.querySelector("[data-pdf-status]");
    this.failed = this.el.querySelector("[data-pdf-failed]");

    this.onKeyDown = (event) => {
      if (event.key === "Escape") this.pushEvent("close_handout", {});
    };
    document.addEventListener("keydown", this.onKeyDown);

    this.el.querySelector("[data-pdf-close]")?.focus({ preventScroll: true });
    this.render();
  },

  destroyed() {
    document.removeEventListener("keydown", this.onKeyDown);
    this.cancelled = true;
    this.task?.destroy();
  },

  async render() {
    try {
      const pdfjs = await loadPdfjs();
      if (this.cancelled) return;

      this.task = pdfjs.getDocument({
        url: this.el.dataset.src,
        isEvalSupported: false,
      });
      const pdf = await this.task.promise;
      const width = this.pages.clientWidth;
      const ratio = Math.min(window.devicePixelRatio || 1, 3);

      for (let number = 1; number <= pdf.numPages; number++) {
        if (this.cancelled) return;
        const page = await pdf.getPage(number);
        const scale = width / page.getViewport({ scale: 1 }).width;
        const viewport = page.getViewport({ scale: scale * ratio });

        const canvas = document.createElement("canvas");
        canvas.width = Math.floor(viewport.width);
        canvas.height = Math.floor(viewport.height);
        canvas.className = "pdf-page";
        canvas.setAttribute("role", "img");
        canvas.setAttribute(
          "aria-label",
          `${this.el.dataset.pageLabel || "Page"} ${number} / ${pdf.numPages}`,
        );
        this.pages.appendChild(canvas);

        await page.render({ canvasContext: canvas.getContext("2d"), viewport })
          .promise;
        if (number === 1) this.status.hidden = true;
      }
    } catch (_error) {
      if (this.cancelled) return;
      this.status.hidden = true;
      this.failed.hidden = false;
    }
  },
};
