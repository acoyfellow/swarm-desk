import gleam/int
import gleam/io
import gleam/list as glist
import gleam/string

pub type FileInfo {
  FileInfo(path: String, exists: Bool, readable: Bool, writable: Bool)
}

pub type DraftError {
  NotFound(path: String)
  NotReadable(path: String)
  NotWritable(path: String)
  NothingToCommit
}

pub opaque type Entry {
  Entry(
    path: String,
    content: String,
    exists: Bool,
    readable: Bool,
    writable: Bool,
    changed: Bool,
    dirty: Bool,
  )
}

pub opaque type Draft {
  Draft(entries: List(Entry), commits: List(String))
}

pub opaque type Done {
  Done(draft: Draft)
}

pub fn seed(path: String, content: String, readable: Bool, writable: Bool) -> Entry {
  Entry(path, content, True, readable, writable, False, False)
}

pub fn slot(path: String) -> Entry {
  Entry(path, "", False, True, True, False, False)
}

pub fn new(entries: List(Entry)) -> Draft {
  Draft(entries, [])
}

pub fn list(d: Draft) -> List(FileInfo) {
  glist.map(d.entries, fn(e) { FileInfo(e.path, e.exists, e.readable, e.writable) })
}

pub fn read(d: Draft, path: String) -> Result(String, DraftError) {
  case glist.find(d.entries, fn(e) { e.path == path }) {
    Error(Nil) -> Error(NotFound(path))
    Ok(e) ->
      case e.exists, e.readable {
        False, _ -> Error(NotFound(path))
        True, False -> Error(NotReadable(path))
        True, True -> Ok(e.content)
      }
  }
}

pub fn write(d: Draft, path: String, content: String) -> Result(Draft, DraftError) {
  case glist.find(d.entries, fn(e) { e.path == path }) {
    Error(Nil) -> Error(NotWritable(path))
    Ok(e) ->
      case e.writable {
        False -> Error(NotWritable(path))
        True -> Ok(Draft(..d, entries: glist.map(d.entries, fn(x) { replace(x, path, content) })))
      }
  }
}

fn replace(entry: Entry, path: String, content: String) -> Entry {
  case entry.path == path {
    True -> Entry(..entry, content: content, exists: True, changed: True, dirty: True)
    False -> entry
  }
}

pub fn diff(d: Draft) -> String {
  d.entries
  |> glist.filter(fn(e) { e.changed })
  |> glist.map(fn(e) { "changed " <> e.path <> " (" <> int.to_string(string.length(e.content)) <> " chars)" })
  |> string.join("\n")
}

pub fn commit(d: Draft, message: String) -> Result(Draft, DraftError) {
  case glist.any(d.entries, fn(e) { e.dirty }) {
    False -> Error(NothingToCommit)
    True ->
      Ok(Draft(
        entries: glist.map(d.entries, fn(e) { Entry(..e, dirty: False) }),
        commits: glist.append(d.commits, [message]),
      ))
  }
}

pub fn done(d: Draft) -> Done {
  Done(d)
}

pub fn describe(e: DraftError) -> String {
  case e {
    NotFound(p) -> "not found: " <> p
    NotReadable(p) -> "not readable: " <> p
    NotWritable(p) -> "not writable: " <> p
    NothingToCommit -> "nothing to commit"
  }
}

fn flag(b: Bool) -> String {
  case b {
    True -> "1"
    False -> "0"
  }
}

pub fn report(finished: Done) -> Nil {
  let d = finished.draft
  glist.each(d.entries, fn(e) {
    io.println(
      "F\t" <> string.inspect(e.path) <> "\t" <> string.inspect(e.content) <> "\t" <> flag(e.exists) <> "\t" <> flag(e.changed) <> "\t" <> flag(e.dirty),
    )
  })
  glist.each(d.commits, fn(c) { io.println("C\t" <> string.inspect(c)) })
  io.println("END")
}
