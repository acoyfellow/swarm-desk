export class DraftError extends Error {
  constructor(kind, path) {
    super(path ? `${kind}: ${path}` : kind);
    this.kind = kind;
    this.path = path;
  }
}

export const seed = (path, content, readable, writable) => ({ path, content, exists: true, readable, writable, changed: false, dirty: false });
export const slot = (path) => ({ path, content: "", exists: false, readable: true, writable: true, changed: false, dirty: false });

export const createDraft = (entries) => {
  const files = entries.map((entry) => ({ ...entry }));
  const commits = [];
  let finished = false;
  const find = (path) => files.find((entry) => entry.path === path);

  const api = {
    list: () => files.map(({ path, exists, readable, writable }) => ({ path, exists, readable, writable })),
    read: (path) => {
      const entry = find(path);
      if (!entry || !entry.exists) throw new DraftError("not found", path);
      if (!entry.readable) throw new DraftError("not readable", path);
      return entry.content;
    },
    write: (path, content) => {
      const entry = find(path);
      if (!entry || !entry.writable) throw new DraftError("not writable", path);
      Object.assign(entry, { content: String(content), exists: true, changed: true, dirty: true });
    },
    diff: () => files.filter((entry) => entry.changed).map((entry) => `changed ${entry.path} (${entry.content.length} chars)`).join("\n"),
    commit: (message) => {
      if (!files.some((entry) => entry.dirty)) throw new DraftError("nothing to commit");
      files.forEach((entry) => { entry.dirty = false; });
      commits.push(String(message));
    },
    done: () => { finished = true; },
  };

  const report = () => {
    const lines = files.map((entry) => `F\t${JSON.stringify(entry.path)}\t${JSON.stringify(entry.content)}\t${entry.exists ? 1 : 0}\t${entry.changed ? 1 : 0}\t${entry.dirty ? 1 : 0}`);
    commits.forEach((message) => lines.push(`C\t${JSON.stringify(message)}`));
    lines.push(finished ? "END" : "NOT_DONE");
    return lines.join("\n");
  };

  return { api: Object.freeze(api), report };
};
