import { readFileSync } from "node:fs";
import vm from "node:vm";
import { createDraft, DraftError, seed, slot } from "./draft.mjs";

const [scriptPath, seedPath] = process.argv.slice(2);
const files = JSON.parse(readFileSync(seedPath, "utf8")).map((f) => (f.slot ? slot(f.path) : seed(f.path, f.content, f.readable, f.writable)));
const { api, report } = createDraft(files);
const source = readFileSync(scriptPath, "utf8");

const sandbox = vm.createContext({ draft: api, DraftError, JSON, Math, String, Number, Array, Object, Error, RegExp, console: { log: () => {} } });
try {
  const result = vm.runInContext(`(async () => {\n${source}\n})()`, sandbox, { timeout: 5000 });
  await Promise.race([result, new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 5000))]);
  console.log(report());
} catch (error) {
  console.log(report());
  console.log(`THROW\t${JSON.stringify(String(error?.message ?? error))}`);
  process.exitCode = 3;
}
