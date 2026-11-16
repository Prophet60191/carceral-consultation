// Copies PDF.js's prebuilt files into the static assets (docs/MATERIALS.md):
// the handout viewer loads them only when someone opens a handout. They are
// modern JavaScript modules, so they are served as they are rather than
// bundled into app.js (built for older browsers). Run by `mix assets.deploy`.
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const from = join(here, "..", "node_modules", "pdfjs-dist", "build");
const to = join(here, "..", "..", "priv", "static", "assets", "pdfjs");

mkdirSync(to, { recursive: true });
for (const file of ["pdf.min.mjs", "pdf.worker.min.mjs"]) {
  copyFileSync(join(from, file), join(to, file));
}
copyFileSync(join(here, "..", "js", "pdfjs_loader.mjs"), join(to, "load.mjs"));
console.log(`PDF.js copied to ${to}`);
