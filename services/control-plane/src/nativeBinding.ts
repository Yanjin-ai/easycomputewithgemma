const pkgProcess = process as NodeJS.Process & { pkg?: unknown };

// When running as a pkg binary, __dirname points to the snapshot FS.
// better-sqlite3 needs its native .node file from the real FS.
if (pkgProcess.pkg) {
  const path = require("path");
  const bindingPath = path.join(path.dirname(process.execPath), "better_sqlite3.node");
  process.env.BETTER_SQLITE3_BINDING = bindingPath;
  process.env.BINDING_PATH = bindingPath;
}
