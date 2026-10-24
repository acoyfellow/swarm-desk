import draft

pub fn main() {
  draft.new([draft.seed("LICENSE", "MIT License\n", True, True)])
  |> fn(d) { draft.report(draft.done(d)) }
}
