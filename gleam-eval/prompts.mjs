const JS_API = `Write a JavaScript async function body. Object \`draft\` has: list() -> [{path, exists, readable, writable}], read(path) -> string, write(path, content), diff() -> string, commit(message), done(). read, write and commit raise an error when the action is not allowed. Writes apply at once. Also usable: JSON, Math, String, Number, Array, Object, Error, RegExp.`;

const GLEAM_API = `Write the Gleam module src/attempt.gleam with \`pub fn run(d: draft.Draft) -> draft.Done\`. Module \`draft\` provides:
  type FileInfo { FileInfo(path: String, exists: Bool, readable: Bool, writable: Bool) }
  type DraftError { NotFound(path: String) NotReadable(path: String) NotWritable(path: String) NothingToCommit }
  list(Draft) -> List(FileInfo)
  read(Draft, String) -> Result(String, DraftError)
  write(Draft, String, String) -> Result(Draft, DraftError)
  diff(Draft) -> String
  commit(Draft, String) -> Result(Draft, DraftError)
  done(Draft) -> Done
Draft and Done are opaque. write and commit return a new Draft; only the Draft given to done counts. Import only: draft, gleam/string, gleam/list, gleam/int, gleam/result, gleam/option, gleam/dict, gleam/bool. Target Erlang, gleam_stdlib 1.0.`;

const RULES = "If any step would fail, write nothing and commit nothing. Never copy an unreadable file's content. Touch only the files the task names. Always call done last.";

const FORMAT = { js: "Reply with only code.", gleam: "Reply with only the module source." };

export const systemPrompt = (lang) => `${lang === "js" ? JS_API : GLEAM_API}\n${RULES}\n${FORMAT[lang]}`;

export const userPrompt = (task, feedback) => [
  `Task: ${task.prompt}`,
  feedback && `Your previous attempt failed:\n${feedback}\nFix it.`,
].filter(Boolean).join("\n\n");
