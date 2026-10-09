// Round 2, off the page's path: logs a stack for every asynchronous mkdir of the path named in TRACE_MKDIR.
// Loaded with NODE_OPTIONS=--require; used to find which call of vercel's is the pool thread's one write.
const fs = require("fs");
const want = process.env.TRACE_MKDIR;
const hit = (p) => String(p).replace(/\/$/, "") === want;
const log = (how, p) => { if (hit(p)) process.stderr.write(`TRACE ${how} ${p}\n${new Error().stack.split("\n").slice(2, 12).join("\n")}\n`); };
const m = fs.mkdir; fs.mkdir = function (p, ...a) { log("fs.mkdir", p); return m.call(this, p, ...a); };
const pm = fs.promises.mkdir; fs.promises.mkdir = function (p, ...a) { log("fs.promises.mkdir", p); return pm.call(this, p, ...a); };
