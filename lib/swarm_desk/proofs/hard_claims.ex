defmodule SwarmDesk.Proofs.HardClaims do
  def all do
    [
      {"sum_odd", "def sumOdd : Nat → Nat\n  | 0 => 0\n  | n + 1 => (2 * n + 1) + sumOdd n\ntheorem sum_odd (n : Nat) : sumOdd n = n * n"},
      {"sum_cubes", "def cubes : Nat → Nat\n  | 0 => 0\n  | n + 1 => (n + 1) ^ 3 + cubes n\ndef tri2 : Nat → Nat\n  | 0 => 0\n  | n + 1 => (n + 1) + tri2 n\ntheorem sum_cubes (n : Nat) : cubes n = tri2 n * tri2 n"},
      {"fib_add", "def fib : Nat → Nat\n  | 0 => 0\n  | 1 => 1\n  | n + 2 => fib n + fib (n + 1)\ntheorem fib_add_two_le (n : Nat) : fib n ≤ fib (n + 1)"},
      {"fib_mono", "def fib2 : Nat → Nat\n  | 0 => 0\n  | 1 => 1\n  | n + 2 => fib2 n + fib2 (n + 1)\ntheorem fib_mono (m n : Nat) (h : m ≤ n) : fib2 m ≤ fib2 n"},
      {"pow_ge_succ", "theorem pow_ge_succ (n : Nat) : n + 1 ≤ 2 ^ n"},
      {"rev_append", "def rev : List Nat → List Nat\n  | [] => []\n  | x :: xs => rev xs ++ [x]\ntheorem rev_append (xs ys : List Nat) : rev (xs ++ ys) = rev ys ++ rev xs"},
      {"rev_rev2", "def rev2 : List Nat → List Nat\n  | [] => []\n  | x :: xs => rev2 xs ++ [x]\ntheorem rev_rev2 (xs : List Nat) : rev2 (rev2 xs) = xs"},
      {"fast_rev", "def revAcc : List Nat → List Nat → List Nat\n  | [], acc => acc\n  | x :: xs, acc => revAcc xs (x :: acc)\ntheorem fast_rev (xs : List Nat) : revAcc xs [] = xs.reverse"},
      {"insert_len", "def ins (x : Nat) : List Nat → List Nat\n  | [] => [x]\n  | y :: ys => if x ≤ y then x :: y :: ys else y :: ins x ys\ntheorem insert_len (x : Nat) (xs : List Nat) : (ins x xs).length = xs.length + 1"},
      {"isort_len", "def ins2 (x : Nat) : List Nat → List Nat\n  | [] => [x]\n  | y :: ys => if x ≤ y then x :: y :: ys else y :: ins2 x ys\ndef isort : List Nat → List Nat\n  | [] => []\n  | x :: xs => ins2 x (isort xs)\ntheorem isort_len (xs : List Nat) : (isort xs).length = xs.length"},
      {"isort_perm_sum", "def ins3 (x : Nat) : List Nat → List Nat\n  | [] => [x]\n  | y :: ys => if x ≤ y then x :: y :: ys else y :: ins3 x ys\ndef isort3 : List Nat → List Nat\n  | [] => []\n  | x :: xs => ins3 x (isort3 xs)\ntheorem isort_perm_sum (xs : List Nat) : (isort3 xs).sum = xs.sum"},
      {"tree_size", "inductive Tree where\n  | leaf : Tree\n  | node : Tree → Nat → Tree → Tree\ndef Tree.size : Tree → Nat\n  | .leaf => 0\n  | .node l _ r => l.size + 1 + r.size\ndef Tree.mirror : Tree → Tree\n  | .leaf => .leaf\n  | .node l v r => .node r.mirror v l.mirror\ntheorem tree_size (t : Tree) : t.mirror.size = t.size"},
      {"mirror_mirror", "inductive T2 where\n  | leaf : T2\n  | node : T2 → Nat → T2 → T2\ndef T2.mirror : T2 → T2\n  | .leaf => .leaf\n  | .node l v r => .node r.mirror v l.mirror\ntheorem mirror_mirror (t : T2) : t.mirror.mirror = t"},
      {"eval_simp", "inductive E where\n  | n : Nat → E\n  | add : E → E → E\n  | mul : E → E → E\ndef E.eval : E → Nat\n  | .n k => k\n  | .add a b => a.eval + b.eval\n  | .mul a b => a.eval * b.eval\ndef E.simp : E → E\n  | .add (.n 0) b => b.simp\n  | .mul (.n 1) b => b.simp\n  | .add a b => .add a.simp b.simp\n  | .mul a b => .mul a.simp b.simp\n  | e => e\ntheorem eval_simp (e : E) : e.simp.eval = e.eval"},
      {"compile_correct", "inductive Ex where\n  | lit : Nat → Ex\n  | plus : Ex → Ex → Ex\ndef Ex.eval : Ex → Nat\n  | .lit k => k\n  | .plus a b => a.eval + b.eval\ninductive I where\n  | push : Nat → I\n  | add : I\ndef run : List I → List Nat → List Nat\n  | [], s => s\n  | .push k :: is, s => run is (k :: s)\n  | .add :: is, b :: a :: s => run is ((a + b) :: s)\n  | .add :: is, s => run is s\ndef compile : Ex → List I\n  | .lit k => [.push k]\n  | .plus a b => compile a ++ compile b ++ [.add]\ntheorem compile_correct (e : Ex) (s : List Nat) : run (compile e) s = e.eval :: s"},
      {"spend_sequence", "def step (used cost cap : Nat) : Nat := if used + cost ≤ cap then used + cost else used\ndef spendAll (cap : Nat) : Nat → List Nat → Nat\n  | used, [] => used\n  | used, c :: cs => spendAll cap (step used c cap) cs\ntheorem spend_sequence (cap used : Nat) (cs : List Nat) (h : used ≤ cap) : spendAll cap used cs ≤ cap"},
      {"route_total", "def route (attack odds : Nat) : Nat := if 50 ≤ attack then 0 else if 85 ≤ odds then 1 else 2\ndef counts : List (Nat × Nat) → Nat × Nat × Nat\n  | [] => (0, 0, 0)\n  | (a, o) :: rest => let (b, x, h) := counts rest; match route a o with\n    | 0 => (b + 1, x, h)\n    | 1 => (b, x + 1, h)\n    | _ => (b, x, h + 1)\ntheorem route_total (xs : List (Nat × Nat)) : (counts xs).1 + (counts xs).2.1 + (counts xs).2.2 = xs.length"},
      {"gcd_comm'", "theorem gcd_comm' (a b : Nat) : Nat.gcd a b = Nat.gcd b a"},
      {"div_mod_id", "theorem div_mod_id (a b : Nat) : b * (a / b) + a % b = a"},
      {"even_or_odd", "theorem even_or_odd (n : Nat) : ∃ k, n = 2 * k ∨ n = 2 * k + 1"},
      {"sq_mod_four", "theorem sq_mod_four (n : Nat) : n * n % 4 = 0 ∨ n * n % 4 = 1"},
      {"three_div", "def digitsum : Nat → Nat\n  | 0 => 0\n  | n + 1 => (n + 1) % 10 + digitsum ((n + 1) / 10)\ndecreasing_by omega\ntheorem three_div_99 : digitsum 99 = 18"},
      {"take_drop", "theorem take_drop' (n : Nat) (xs : List Nat) : xs.take n ++ xs.drop n = xs"},
      {"map_comp", "theorem map_comp' (f g : Nat → Nat) (xs : List Nat) : (xs.map g).map f = xs.map (fun x => f (g x))"},
      {"filter_append", "theorem filter_append' (p : Nat → Bool) (xs ys : List Nat) : (xs ++ ys).filter p = xs.filter p ++ ys.filter p"},
      {"sum_le_len_max", "def mx : List Nat → Nat\n  | [] => 0\n  | x :: xs => max x (mx xs)\ntheorem sum_le_len_max (xs : List Nat) : xs.sum ≤ xs.length * mx xs"},
      {"all_le_max", "def mx2 : List Nat → Nat\n  | [] => 0\n  | x :: xs => max x (mx2 xs)\ntheorem all_le_max (xs : List Nat) (x : Nat) (h : x ∈ xs) : x ≤ mx2 xs"},
      {"zip_len", "theorem zip_len' (xs ys : List Nat) : (xs.zip ys).length = min xs.length ys.length"},
      {"nat_strong", "def half : Nat → Nat\n  | 0 => 0\n  | 1 => 0\n  | n + 2 => half n + 1\ntheorem half_le (n : Nat) : half n ≤ n"},
      {"half_double", "def half2 : Nat → Nat\n  | 0 => 0\n  | 1 => 0\n  | n + 2 => half2 n + 1\ntheorem half_double (n : Nat) : half2 (2 * n) = n"}
    ]
  end
end
