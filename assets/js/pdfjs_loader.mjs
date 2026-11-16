// Loaded as a module by the handout viewer (assets/js/pdf_viewer.js), from
// /assets/pdfjs/load.mjs beside PDF.js's own files (assets/scripts/copy-pdfjs.mjs).
import * as pdfjs from "./pdf.min.mjs";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "./pdf.worker.min.mjs",
  import.meta.url,
).href;
window.ccPdfjs = pdfjs;
window.dispatchEvent(new Event("cc:pdfjs-ready"));
