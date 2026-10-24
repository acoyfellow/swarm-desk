defmodule SwarmDesk.Proofs.Claims do
  def all do
    [
      {"add_zero_left", "theorem add_zero_left (n : Nat) : 0 + n = n"},
      {"add_comm'", "theorem add_comm' (a b : Nat) : a + b = b + a"},
      {"mul_two", "theorem mul_two' (n : Nat) : n * 2 = n + n"},
      {"len_append", "theorem len_append (xs ys : List Nat) : (xs ++ ys).length = xs.length + ys.length"},
      {"rev_rev", "theorem rev_rev (xs : List Nat) : xs.reverse.reverse = xs"},
      {"map_len", "theorem map_len (f : Nat → Nat) (xs : List Nat) : (xs.map f).length = xs.length"},
      {"min_le", "theorem min_le' (a b : Nat) : min a b ≤ a"},
      {"cap_never_exceeds", "def spend (used cost cap : Nat) : Nat := if used + cost ≤ cap then used + cost else used\ntheorem cap_never_exceeds (u c cap : Nat) (h : u ≤ cap) : spend u c cap ≤ cap"},
      {"clamp_in_range", "def clamp (lo hi x : Nat) : Nat := max lo (min hi x)\ntheorem clamp_in_range (lo hi x : Nat) (h : lo ≤ hi) : lo ≤ clamp lo hi x ∧ clamp lo hi x ≤ hi"},
      {"sum_append", "def sum : List Nat → Nat\n  | [] => 0\n  | x :: xs => x + sum xs\ntheorem sum_append (xs ys : List Nat) : sum (xs ++ ys) = sum xs + sum ys"},
      {"filter_len_le", "theorem filter_len_le (p : Nat → Bool) (xs : List Nat) : (xs.filter p).length ≤ xs.length"},
      {"double_even", "theorem double_even (n : Nat) : (2 * n) % 2 = 0"},
      {"gauss", "def tri : Nat → Nat\n  | 0 => 0\n  | n + 1 => (n + 1) + tri n\ntheorem gauss (n : Nat) : 2 * tri n = n * (n + 1)"},
      {"act_only_when_sure", "def act (odds : Nat) : Bool := decide (85 ≤ odds)\ntheorem act_only_when_sure (o : Nat) (h : act o = true) : 85 ≤ o"},
      {"blocked_never_acts", "def route (attack odds : Nat) : String := if 50 ≤ attack then \"blocked\" else if 85 ≤ odds then \"act\" else \"human\"\ntheorem blocked_never_acts (a o : Nat) (h : 50 ≤ a) : route a o ≠ \"act\""},
      {"len_replicate", "theorem len_replicate (n x : Nat) : (List.replicate n x).length = n"},
      {"append_nil'", "theorem append_nil' (xs : List Nat) : xs ++ [] = xs"},
      {"pow_two_pos", "theorem pow_two_pos (n : Nat) : 0 < 2 ^ n"},
      {"max_comm'", "theorem max_comm' (a b : Nat) : max a b = max b a"},
      {"sub_le'", "theorem sub_le' (a b : Nat) : a - b ≤ a"},
      {"rev_len", "theorem rev_len (xs : List Nat) : xs.reverse.length = xs.length"},
      {"take_len_le", "theorem take_len_le (n : Nat) (xs : List Nat) : (xs.take n).length ≤ n"},
      {"all_filter", "theorem all_filter (p : Nat → Bool) (xs : List Nat) : (xs.filter p).all p = true"},
      {"count_le_len", "def count (p : Nat → Bool) : List Nat → Nat\n  | [] => 0\n  | x :: xs => (if p x then 1 else 0) + count p xs\ntheorem count_le_len (p : Nat → Bool) (xs : List Nat) : count p xs ≤ xs.length"},
      {"odd_sq", "theorem odd_sq (n : Nat) (h : n % 2 = 1) : (n * n) % 2 = 1"},
      {"mono_spend", "def spend2 (used cost cap : Nat) : Nat := if used + cost ≤ cap then used + cost else used\ntheorem mono_spend (u c cap : Nat) : u ≤ spend2 u c cap"},
      {"dedup_len_le", "theorem dedup_len_le (xs : List Nat) : xs.eraseDups.length ≤ xs.length"},
      {"sum_map_const", "def total : List Nat → Nat\n  | [] => 0\n  | x :: xs => x + total xs\ntheorem sum_map_const (xs : List Nat) : total (xs.map (fun _ => 1)) = xs.length"},
      {"lt_irrefl'", "theorem lt_irrefl' (n : Nat) : ¬ n < n"},
      {"two_le_sq", "theorem two_le_sq (n : Nat) (h : 2 ≤ n) : 2 * n ≤ n * n"}
    ]
  end
end
