import Vos.Spec.Sched
import Vos.Types

/-!
Cooperative and priority scheduling over a fixed task table.

Switching happens only in `dispatch`. It selects the current task again, or
a task that is already on the ready list. A blocked task is neither, so it
is not selected (`dispatch_not_blocked`). Under `Policy.priority` the
selected task is a highest-priority ready task (`priority_max`). A delay
blocks the current task until `now` reaches the deadline
(`ticks_before_deadline`).
-/
namespace Vos.Sched

open Vos
open Vos.Spec.Sched

variable {n : Nat}

def readyPush (r : List (Fin n)) (i : Fin n) : List (Fin n) :=
  if r.contains i then r else r ++ [i]

theorem readyPush_nodup {r : List (Fin n)} {i : Fin n} (h : r.Nodup) :
    (readyPush r i).Nodup := by
  unfold readyPush
  split
  · exact h
  · grind

theorem readyPush_mem {r : List (Fin n)} {i j : Fin n} :
    j ∈ readyPush r i ↔ j ∈ r ∨ j = i := by
  unfold readyPush
  grind

theorem readyPush_of_not_mem {r : List (Fin n)} {i : Fin n} (h : i ∉ r) :
    readyPush r i = r ++ [i] := by
  simp [readyPush, List.contains_iff_mem, h]

def activate (s : Sched n) (i : Fin n) : Sched n :=
  { s with ready := s.ready.erase i, current := some i }

def demoteOf (s : Sched n) (c : Fin n) : Sched n :=
  { s with ready := readyPush s.ready c, current := none }

/-- Put an idle slot on the ready list. `p` is its priority afterwards. -/
def promote (s : Sched n) (i : Fin n) (p : Prio) : Sched n where
  park := fun j => if j = i then .alive else s.park j
  prio := fun j => if j = i then p else s.prio j
  deadline := s.deadline
  onDelay := fun j => if j = i then false else s.onDelay j
  ready := readyPush s.ready i
  current := s.current
  now := s.now

def blockCurrent (s : Sched n) (deadline : Nat) (onDelay : Bool) : Sched n :=
  match s.current with
  | none => s
  | some c =>
    { s with
      park := fun j => if j = c then .blocked else s.park j
      onDelay := fun j => if j = c then onDelay else s.onDelay j
      deadline := fun j => if j = c then deadline else s.deadline j
      ready := s.ready.erase c
      current := none }

def exitCurrent (s : Sched n) : Sched n :=
  match s.current with
  | none => s
  | some c =>
    { s with
      park := fun j => if j = c then .terminated else s.park j
      onDelay := fun j => if j = c then false else s.onDelay j
      ready := s.ready.erase c
      current := none }

/-- Highest priority in `r`. Equal priorities keep the earlier entry. -/
def pickMax (s : Sched n) : List (Fin n) → Option (Fin n)
  | [] => none
  | i :: r =>
    match pickMax s r with
    | none => some i
    | some b => if s.prio b > s.prio i then some b else some i

def choose (s : Sched n) (p : Policy) : Option (Fin n) :=
  match p with
  | .cooperative =>
    match s.current with
    | some c => some c
    | none => s.ready.head?
  | .priority =>
    match pickMax s s.ready with
    | none => s.current
    | some i =>
      match s.current with
      | none => some i
      | some c => if s.prio i > s.prio c then some i else some c

inductive Chosen (s : Sched n) : Option (Fin n) → Prop where
  | idle : Chosen s none
  | same (i : Fin n) : s.current = some i → Chosen s (some i)
  | ready (i : Fin n) : i ∈ s.ready → Chosen s (some i)

def applyChoice (s : Sched n) : Option (Fin n) → Sched n
  | none => s
  | some i =>
    match s.current with
    | none => activate s i
    | some c => if c = i then s else activate (demoteOf s c) i

def dispatch (s : Sched n) (p : Policy) : Sched n :=
  applyChoice s (choose s p)

def findUnused (s : Sched n) : Option (Fin n) :=
  (List.finRange n).find? fun i => s.park i == .unused

def spawn (s : Sched n) (p : Policy) (prio : Prio) : Sched n × Option (Fin n) :=
  match findUnused s with
  | none => (s, none)
  | some i => (dispatch (promote s i prio) p, some i)

def yieldTask (s : Sched n) (p : Policy) : Sched n :=
  match s.current with
  | none => dispatch s p
  | some c => dispatch (demoteOf s c) p

def block (s : Sched n) (p : Policy) : Sched n :=
  dispatch (blockCurrent s 0 false) p

def delay (s : Sched n) (p : Policy) (dt : Nat) : Sched n :=
  if dt = 0 then yieldTask s p
  else dispatch (blockCurrent s (s.now + dt) true) p

def unblock (s : Sched n) (p : Policy) (i : Fin n) : Sched n :=
  if s.park i == .blocked then dispatch (promote s i (s.prio i)) p else s

def exitTask (s : Sched n) (p : Policy) : Sched n :=
  dispatch (exitCurrent s) p

def due (s : Sched n) (i : Fin n) : Bool :=
  s.park i == .blocked && s.onDelay i && decide (s.deadline i ≤ s.now)

def wakeOne (s : Sched n) (i : Fin n) : Sched n :=
  if due s i then promote s i (s.prio i) else s

def wakeDue (s : Sched n) : Sched n :=
  (List.finRange n).foldl (fun acc i => wakeOne acc i) s

def tick (s : Sched n) (p : Policy) : Sched n :=
  dispatch (wakeDue { s with now := s.now + 1 }) p

def afterTicks (s : Sched n) (p : Policy) : Nat → Sched n
  | 0 => s
  | k + 1 => afterTicks (tick s p) p k

theorem empty_inv : Inv (Sched.empty n) := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp [Sched.empty]
  · intro i hi; simp [Sched.empty] at hi
  · intro i hi; simp [Sched.empty] at hi
  · intro i hi; simp [Sched.empty] at hi
  · intro i hi; simp [Sched.empty] at hi
  · intro i hi
    refine ⟨?_, ?_⟩ <;> simp [Sched.empty]
  · intro i hi; simp [Sched.empty] at hi
  · intro i hi; simp [Sched.empty] at hi

theorem ready_bounded (s : Sched n) (h : Inv s) : readyBounded s := by
  unfold readyBounded
  have hle := h.ready_nodup.length_le_of_subset (l₂ := List.finRange n)
    (fun _ _ => List.mem_finRange _)
  simpa [List.length_finRange] using hle

theorem current_is_running (s : Sched n) (i : Fin n) (hc : s.current = some i) :
    phase s i = .running := by
  simp [phase, hc]

theorem not_blocked (s : Sched n) : notBlocked s := by
  intro i hp hc
  simp [phase, hc] at hp

theorem ready_alive (s : Sched n) (h : Inv s) (i : Fin n) (hm : i ∈ s.ready) :
    s.park i = .alive := by
  cases hp : s.park i with
  | alive => rfl
  | blocked => exact absurd hm (h.blocked_idle i hp).1
  | unused => exact absurd hm (h.unused_idle i hp).1
  | terminated => exact absurd hm (h.terminated_idle i hp).1

theorem phase_ready_iff (s : Sched n) (h : Inv s) (i : Fin n) :
    phase s i = .ready ↔ i ∈ s.ready := by
  constructor
  · intro hp
    unfold phase at hp
    split at hp
    · next hc => simp at hp
    · next hc =>
      split at hp
      · next hr =>
        exact (List.contains_iff_mem).1 hr
      · next hr =>
        cases hpark : s.park i with
        | alive =>
          simp [hpark] at hp
          have hlive := h.alive_live i hpark
          cases hlive with
          | inl hm =>
            exact False.elim (hr ((List.contains_iff_mem).2 hm))
          | inr hc' =>
            exact absurd hc' hc
        | unused => simp [hpark] at hp
        | blocked => simp [hpark] at hp
        | terminated => simp [hpark] at hp
  · intro hm
    have hc : ¬ s.current = some i := fun hc => h.current_not_ready i hc hm
    unfold phase
    simp [hc, hm]

theorem phase_blocked_iff (s : Sched n) (h : Inv s) (i : Fin n) :
    phase s i = .blocked ↔ s.park i = .blocked := by
  constructor
  · intro hp
    unfold phase at hp
    split at hp
    · next hc => simp at hp
    · next hc =>
      split at hp
      · next hr => simp at hp
      · next hr =>
        cases hpark : s.park i with
        | blocked => rfl
        | alive => simp [hpark] at hp
        | unused => simp [hpark] at hp
        | terminated => simp [hpark] at hp
  · intro hp
    have ⟨hnr, hnc⟩ := h.blocked_idle i hp
    unfold phase
    simp [hnc, hnr, hp]

theorem blocked_not_current (s : Sched n) (h : Inv s) (i : Fin n) :
    phase s i = .blocked → s.current ≠ some i :=
  fun hp hc => (h.blocked_idle i ((phase_blocked_iff s h i).1 hp)).2 hc

theorem activate_inv (s : Sched n) (h : Inv s) (i : Fin n)
    (hmem : i ∈ s.ready) (hcur : s.current = none) : Inv (activate s i) := by
  have halive : s.park i = .alive := ready_alive s h i hmem
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simpa [activate] using h.ready_nodup.erase i
  · intro j hj
    simp [activate] at hj
    cases hj
    exact h.ready_nodup.not_mem_erase
  · intro j hj
    simp [activate] at hj
    cases hj
    simpa [activate] using halive
  · intro j hj
    have hj' : s.park j = .alive := by simpa [activate] using hj
    have hlive := h.alive_live j hj'
    simp [activate]
    cases hlive with
    | inl hm =>
      by_cases hji : j = i
      · exact Or.inr (by simpa [hji])
      · exact Or.inl ((h.ready_nodup.mem_erase_iff).2 ⟨hji, hm⟩)
    | inr hc =>
      simp [hcur] at hc
  · intro j hj
    have hj' : s.park j = .blocked := by simpa [activate] using hj
    have ⟨hnr, hnc⟩ := h.blocked_idle j hj'
    refine ⟨?_, ?_⟩
    · intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 (by simpa [activate] using hm)).2
    · intro hc
      simp [activate] at hc
      cases hc
      simp [halive] at hj'
  · intro j hj
    have hj' : s.park j = .unused := by simpa [activate] using hj
    have ⟨hnr, hnc⟩ := h.unused_idle j hj'
    refine ⟨?_, ?_⟩
    · intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 (by simpa [activate] using hm)).2
    · intro hc
      simp [activate] at hc
      cases hc
      simp [halive] at hj'
  · intro j hj
    have hj' : s.park j = .terminated := by simpa [activate] using hj
    have ⟨hnr, _hnc⟩ := h.terminated_idle j hj'
    refine ⟨?_, ?_⟩
    · intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 (by simpa [activate] using hm)).2
    · intro hc
      simp [activate] at hc
      cases hc
      simp [halive] at hj'
  · intro j hj
    exact h.delay_blocked j (by simpa [activate] using hj)

theorem demote_inv (s : Sched n) (h : Inv s) (c : Fin n) (hc : s.current = some c) :
    Inv (demoteOf s c) := by
  have halive : s.park c = .alive := h.current_alive c hc
  have hnot : c ∉ s.ready := h.current_not_ready c hc
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simpa [demoteOf] using readyPush_nodup h.ready_nodup
  · intro i hi
    simp [demoteOf] at hi
  · intro i hi
    simp [demoteOf] at hi
  · intro j hj
    have hj' : s.park j = .alive := by simpa [demoteOf] using hj
    have hlive := h.alive_live j hj'
    simp [demoteOf]
    cases hlive with
    | inl hm =>
      exact (readyPush_mem).2 (Or.inl hm)
    | inr hcur =>
      have heq : j = c := by
        exact (by simpa [hc] using hcur : c = j).symm
      exact (readyPush_mem).2 (Or.inr heq)
  · intro j hj
    have hj' : s.park j = .blocked := by simpa [demoteOf] using hj
    have ⟨hnr, _⟩ := h.blocked_idle j hj'
    have hne : j ≠ c := by
      intro heq
      simp [heq, halive] at hj'
    refine ⟨?_, by simp [demoteOf]⟩
    intro hm
    have hmem := (readyPush_mem).1 (by simpa [demoteOf] using hm)
    cases hmem with
    | inl h => exact hnr h
    | inr h => exact hne h
  · intro j hj
    have hj' : s.park j = .unused := by simpa [demoteOf] using hj
    have ⟨hnr, _⟩ := h.unused_idle j hj'
    have hne : j ≠ c := by
      intro heq
      simp [heq, halive] at hj'
    refine ⟨?_, by simp [demoteOf]⟩
    intro hm
    have hmem := (readyPush_mem).1 (by simpa [demoteOf] using hm)
    cases hmem with
    | inl h => exact hnr h
    | inr h => exact hne h
  · intro j hj
    have hj' : s.park j = .terminated := by simpa [demoteOf] using hj
    have ⟨hnr, _⟩ := h.terminated_idle j hj'
    have hne : j ≠ c := by
      intro heq
      simp [heq, halive] at hj'
    refine ⟨?_, by simp [demoteOf]⟩
    intro hm
    have hmem := (readyPush_mem).1 (by simpa [demoteOf] using hm)
    cases hmem with
    | inl h => exact hnr h
    | inr h => exact hne h
  · intro j hj
    exact h.delay_blocked j (by simpa [demoteOf] using hj)

theorem promote_inv (s : Sched n) (h : Inv s) (i : Fin n)
    (hidle : i ∉ s.ready ∧ s.current ≠ some i) : Inv (promote s i (s.prio i)) := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simpa [promote] using readyPush_nodup h.ready_nodup
  · intro j hj
    have hc : s.current = some j := by simpa [promote] using hj
    have hne : j ≠ i := by
      intro heq
      exact hidle.2 (heq ▸ hc)
    intro hm
    have hmem := (readyPush_mem).1 (by simpa [promote] using hm)
    cases hmem with
    | inl hmem => exact h.current_not_ready j hc hmem
    | inr hmem => exact hne hmem
  · intro j hj
    have hc : s.current = some j := by simpa [promote] using hj
    have hne : j ≠ i := by
      intro heq
      exact hidle.2 (heq ▸ hc)
    simpa [promote, hne] using h.current_alive j hc
  · intro j hj
    by_cases hji : j = i
    · subst hji
      exact Or.inl (by simpa [promote] using (readyPush_mem).2 (Or.inr rfl))
    · have hj' : s.park j = .alive := by simpa [promote, hji] using hj
      have hlive := h.alive_live j hj'
      cases hlive with
      | inl hm =>
        exact Or.inl (by simpa [promote] using (readyPush_mem).2 (Or.inl hm))
      | inr hc =>
        exact Or.inr (by simpa [promote] using hc)
  · intro j hj
    by_cases hji : j = i
    · subst hji
      simp [promote] at hj
    · have hj' : s.park j = .blocked := by simpa [promote, hji] using hj
      have ⟨hnr, hnc⟩ := h.blocked_idle j hj'
      refine ⟨?_, ?_⟩
      · intro hm
        have hmem := (readyPush_mem).1 (by simpa [promote] using hm)
        cases hmem with
        | inl h => exact hnr h
        | inr h => exact hji h
      · simpa [promote] using hnc
  · intro j hj
    by_cases hji : j = i
    · subst hji
      simp [promote] at hj
    · have hj' : s.park j = .unused := by simpa [promote, hji] using hj
      have ⟨hnr, hnc⟩ := h.unused_idle j hj'
      refine ⟨?_, ?_⟩
      · intro hm
        have hmem := (readyPush_mem).1 (by simpa [promote] using hm)
        cases hmem with
        | inl h => exact hnr h
        | inr h => exact hji h
      · simpa [promote] using hnc
  · intro j hj
    by_cases hji : j = i
    · subst hji
      simp [promote] at hj
    · have hj' : s.park j = .terminated := by simpa [promote, hji] using hj
      have ⟨hnr, hnc⟩ := h.terminated_idle j hj'
      refine ⟨?_, ?_⟩
      · intro hm
        have hmem := (readyPush_mem).1 (by simpa [promote] using hm)
        cases hmem with
        | inl h => exact hnr h
        | inr h => exact hji h
      · simpa [promote] using hnc
  · intro j hj
    by_cases hji : j = i
    · subst hji
      simp [promote] at hj
    · have ho : s.onDelay j = true := by simpa [promote, hji] using hj
      simpa [promote, hji] using h.delay_blocked j ho

theorem pickMax_none (s : Sched n) (r : List (Fin n)) (h : pickMax s r = none) : r = [] := by
  cases r with
  | nil => rfl
  | cons i r =>
    simp [pickMax] at h
    cases hrec : pickMax s r with
    | none => simp [hrec] at h
    | some b =>
      simp [hrec] at h
      split at h <;> simp at h

theorem pickMax_some (s : Sched n) (r : List (Fin n)) (m : Fin n)
    (h : pickMax s r = some m) :
    m ∈ r ∧ ∀ j, j ∈ r → s.prio j ≤ s.prio m := by
  induction r generalizing m with
  | nil => simp [pickMax] at h
  | cons i r ih =>
    simp [pickMax] at h
    cases hrec : pickMax s r with
    | none =>
      have hr : r = [] := pickMax_none s r hrec
      subst hr
      simp [hrec] at h
      cases h
      simp
    | some b =>
      simp [hrec] at h
      have ⟨hb, hmax⟩ := ih b hrec
      split at h
      · rename_i hgt
        cases h
        refine ⟨List.mem_cons.2 (Or.inr hb), ?_⟩
        intro j hj
        rw [List.mem_cons] at hj
        cases hj with
        | inl heq =>
          subst heq
          exact Nat.le_of_lt hgt
        | inr hj =>
          exact hmax j hj
      · rename_i hng
        cases h
        refine ⟨List.mem_cons.2 (Or.inl rfl), ?_⟩
        intro j hj
        rw [List.mem_cons] at hj
        cases hj with
        | inl heq =>
          subst heq
          exact Nat.le_refl _
        | inr hj =>
          exact Nat.le_trans (hmax j hj) (Nat.le_of_not_lt hng)

theorem choose_chosen (s : Sched n) (h : Inv s) (p : Policy) : Chosen s (choose s p) := by
  cases p with
  | cooperative =>
    cases hc : s.current with
    | some c =>
      simp [choose, hc]
      exact Chosen.same c hc
    | none =>
      cases hr : s.ready with
      | nil =>
        simp [choose, hc, hr]
        exact Chosen.idle
      | cons i rest =>
        simp [choose, hc, hr]
        exact Chosen.ready i (by simp [hr])
  | priority =>
    cases hm : pickMax s s.ready with
    | none =>
      cases hc : s.current with
      | none =>
        simp [choose, hm, hc]
        exact Chosen.idle
      | some c =>
        simp [choose, hm, hc]
        exact Chosen.same c hc
    | some i =>
      have ⟨hmem, _⟩ := pickMax_some s s.ready i hm
      cases hc : s.current with
      | none =>
        simp [choose, hm, hc]
        exact Chosen.ready i hmem
      | some c =>
        simp [choose, hm, hc]
        split
        · exact Chosen.ready i hmem
        · exact Chosen.same c hc

theorem applyChoice_inv (s : Sched n) (h : Inv s) (choice : Option (Fin n))
    (hc : Chosen s choice) : Inv (applyChoice s choice) := by
  cases hc with
  | idle =>
    simp [applyChoice]
    exact h
  | same i hcur =>
    simp [applyChoice, hcur]
    exact h
  | ready i hmem =>
    cases hcurrent : s.current with
    | none =>
      simp [applyChoice, hcurrent]
      exact activate_inv s h i hmem hcurrent
    | some c =>
      have hne : c ≠ i := by
        intro heq
        exact h.current_not_ready i (heq ▸ hcurrent) hmem
      simp [applyChoice, hcurrent, hne]
      have hdem := demote_inv s h c hcurrent
      have hmem' : i ∈ (demoteOf s c).ready := by
        have : i ∈ readyPush s.ready c := (readyPush_mem).2 (Or.inl hmem)
        simpa [demoteOf] using this
      have hcur' : (demoteOf s c).current = none := by simp [demoteOf]
      exact activate_inv (demoteOf s c) hdem i hmem' hcur'

theorem dispatch_inv (s : Sched n) (h : Inv s) (p : Policy) : Inv (dispatch s p) :=
  applyChoice_inv s h (choose s p) (choose_chosen s h p)

theorem applyChoice_current (s : Sched n) (choice : Option (Fin n)) :
    (applyChoice s choice).current = s.current ∨ (applyChoice s choice).current = choice := by
  cases choice with
  | none =>
    simp [applyChoice]
  | some i =>
    cases hc : s.current with
    | none =>
      simp [applyChoice, hc, activate]
    | some c =>
      by_cases hci : c = i
      · simp [applyChoice, hc, hci]
      · simp [applyChoice, hc, hci, activate, demoteOf]

theorem choose_not (s : Sched n) (h : Inv s) (p : Policy) (i : Fin n)
    (hc : s.current ≠ some i) (hr : i ∉ s.ready) : choose s p ≠ some i := by
  cases p with
  | cooperative =>
    cases hcur : s.current with
    | some c =>
      simp [choose, hcur]
      intro heq
      apply hc
      simp [hcur, heq]
    | none =>
      cases hready : s.ready with
      | nil =>
        simp [choose, hcur, hready]
      | cons j rest =>
        simp [choose, hcur, hready]
        intro heq
        apply hr
        simp [hready, heq]
  | priority =>
    cases hm : pickMax s s.ready with
    | none =>
      cases hcur : s.current with
      | none => simp [choose, hm, hcur]
      | some c =>
        simp [choose, hm, hcur]
        intro heq
        apply hc
        simp [hcur, heq]
    | some m =>
      have ⟨hmem, _⟩ := pickMax_some s s.ready m hm
      cases hcur : s.current with
      | none =>
        simp [choose, hm, hcur]
        intro heq
        apply hr
        simp [heq] at hmem
        exact hmem
      | some c =>
        simp [choose, hm, hcur]
        split
        · intro heq
          apply hr
          cases heq
          exact hmem
        · intro heq
          apply hc
          simp [hcur, heq]

theorem chosen_some {choice : Option (Fin n)} (s : Sched n) (hch : Chosen s choice) :
    match choice with
    | none => True
    | some i => s.current = some i ∨ i ∈ s.ready := by
  cases hch with
  | idle => trivial
  | same i hj => exact Or.inl hj
  | ready i hj => exact Or.inr hj

/-- The task `dispatch` runs was already current, or it was ready. It was not blocked. -/
theorem dispatch_not_blocked (s : Sched n) (h : Inv s) (p : Policy) (i : Fin n)
    (hc : (dispatch s p).current = some i) : phase s i ≠ .blocked := by
  have hcur := applyChoice_current s (choose s p)
  simp [dispatch] at hc
  cases hcur with
  | inl hsame =>
    have hwas : s.current = some i := by simpa [hsame] using hc
    simp [current_is_running s i hwas]
  | inr hchoice =>
    have hwas : choose s p = some i := by simpa [hchoice] using hc
    cases p with
    | cooperative =>
      cases hc0 : s.current with
      | some c =>
        simp [choose, hc0] at hwas
        cases hwas
        simp [current_is_running s i hc0]
      | none =>
        cases hr : s.ready with
        | nil => simp [choose, hc0, hr] at hwas
        | cons j rest =>
          simp [choose, hc0, hr] at hwas
          cases hwas
          simp [(phase_ready_iff s h i).2 (by simp [hr])]
    | priority =>
      cases hm : pickMax s s.ready with
      | none =>
        have hwas' : s.current = some i := by simpa [choose, hm] using hwas
        simp [current_is_running s i hwas']
      | some m =>
        have ⟨hmem, _⟩ := pickMax_some s s.ready m hm
        cases hc0 : s.current with
        | none =>
          simp [choose, hm, hc0] at hwas
          cases hwas
          simp [(phase_ready_iff s h i).2 hmem]
        | some c =>
          by_cases hgt : s.prio m > s.prio c
          · simp [choose, hm, hc0, hgt] at hwas
            cases hwas
            simp [(phase_ready_iff s h i).2 hmem]
          · simp [choose, hm, hc0, hgt] at hwas
            cases hwas
            simp [current_is_running s i hc0]

theorem dispatch_same_fields (s : Sched n) (p : Policy) (i : Fin n) :
    (dispatch s p).park i = s.park i ∧ (dispatch s p).onDelay i = s.onDelay i ∧
      (dispatch s p).deadline i = s.deadline i ∧ (dispatch s p).now = s.now ∧
      (dispatch s p).prio i = s.prio i := by
  simp [dispatch, applyChoice]
  cases choose s p with
  | none => simp
  | some j =>
    cases hc : s.current with
    | none => simp [applyChoice, hc, activate]
    | some c =>
      by_cases hci : c = j
      · simp [applyChoice, hc, hci]
      · simp [applyChoice, hc, hci, activate, demoteOf]

theorem findUnused_spec (s : Sched n) (i : Fin n) (h : findUnused s = some i) :
    s.park i = .unused := by
  have happ := List.find?_eq_some_iff_append.mp h
  have hb : (s.park i == .unused) = true := happ.1
  exact (beq_iff_eq).1 hb

theorem spawn_inv (s : Sched n) (h : Inv s) (p : Policy) (prio : Prio) :
    Inv (spawn s p prio).1 := by
  unfold spawn
  cases hf : findUnused s with
  | none =>
    simp [hf]
    exact h
  | some i =>
    simp [hf]
    have hun := findUnused_spec s i hf
    have hidle := h.unused_idle i hun
    have hprom : Inv (promote s i (s.prio i)) := promote_inv s h i hidle
    -- spawn promotes with `prio`, not `s.prio i`. Priority is not part of `Inv`.
    have hprom' : Inv (promote s i prio) := by
      have hsame : (promote s i prio).park = (promote s i (s.prio i)).park := by
        funext j; simp [promote]
      have hready : (promote s i prio).ready = (promote s i (s.prio i)).ready := by
        simp [promote]
      have hcur : (promote s i prio).current = (promote s i (s.prio i)).current := by
        simp [promote]
      have hon : (promote s i prio).onDelay = (promote s i (s.prio i)).onDelay := by
        funext j; simp [promote]
      -- Rebuild the invariant from the other promotion. The fields `Inv` reads agree.
      refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
      · simpa [hready] using hprom.ready_nodup
      · simpa [hready, hcur] using hprom.current_not_ready
      · intro j hj
        have := hprom.current_alive j (by simpa [hcur] using hj)
        simpa [hsame] using this
      · intro j hj
        have := hprom.alive_live j (by simpa [hsame] using hj)
        simpa [hready, hcur] using this
      · intro j hj
        have := hprom.blocked_idle j (by simpa [hsame] using hj)
        simpa [hready, hcur] using this
      · intro j hj
        have := hprom.unused_idle j (by simpa [hsame] using hj)
        simpa [hready, hcur] using this
      · intro j hj
        have := hprom.terminated_idle j (by simpa [hsame] using hj)
        simpa [hready, hcur] using this
      · intro j hj
        exact hprom.delay_blocked j (by simpa [hon] using hj)
    exact dispatch_inv (promote s i prio) hprom' p

theorem yield_inv (s : Sched n) (h : Inv s) (p : Policy) : Inv (yieldTask s p) := by
  unfold yieldTask
  cases hc : s.current with
  | none =>
    simp [hc]
    exact dispatch_inv s h p
  | some c =>
    simp [hc]
    exact dispatch_inv (demoteOf s c) (demote_inv s h c hc) p

theorem blockCurrent_eq (s : Sched n) (c : Fin n) (d : Nat) (od : Bool)
    (hc : s.current = some c) :
    blockCurrent s d od = {
      s with
      park := fun j => if j = c then .blocked else s.park j
      onDelay := fun j => if j = c then od else s.onDelay j
      deadline := fun j => if j = c then d else s.deadline j
      ready := s.ready.erase c
      current := none } := by
  simp [blockCurrent, hc]

theorem blockCurrent_inv (s : Sched n) (h : Inv s) (d : Nat) (od : Bool) :
    Inv (blockCurrent s d od) := by
  cases hc : s.current with
  | none =>
    simp [blockCurrent, hc]
    exact h
  | some c =>
    have halive : s.park c = .alive := h.current_alive c hc
    rw [blockCurrent_eq s c d od hc]
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · exact h.ready_nodup.erase c
    · intro i hi
      simp at hi
    · intro i hi
      simp at hi
    · intro j hj
      have hne : j ≠ c := by
        intro heq
        simp [heq] at hj
      have hj' : s.park j = .alive := by simpa [hne] using hj
      have hlive := h.alive_live j hj'
      cases hlive with
      | inl hm =>
        exact Or.inl ((h.ready_nodup.mem_erase_iff).2 ⟨hne, hm⟩)
      | inr hcur =>
        have heq : j = c := by
          exact (by simpa [hc] using hcur : c = j).symm
        exact absurd heq hne
    · intro j hj
      by_cases hji : j = c
      · subst hji
        refine ⟨h.ready_nodup.not_mem_erase, ?_⟩
        simp
      · have hj' : s.park j = .blocked := by simpa [hji] using hj
        have ⟨hnr, _⟩ := h.blocked_idle j hj'
        refine ⟨?_, by simp⟩
        intro hm
        exact hnr ((h.ready_nodup.mem_erase_iff).1 hm).2
    · intro j hj
      have hne : j ≠ c := by
        intro heq
        simp [heq, halive] at hj
      have hj' : s.park j = .unused := by simpa [hne] using hj
      have ⟨hnr, _⟩ := h.unused_idle j hj'
      refine ⟨?_, by simp⟩
      intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 hm).2
    · intro j hj
      have hne : j ≠ c := by
        intro heq
        simp [heq, halive] at hj
      have hj' : s.park j = .terminated := by simpa [hne] using hj
      have ⟨hnr, _⟩ := h.terminated_idle j hj'
      refine ⟨?_, by simp⟩
      intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 hm).2
    · intro j hj
      by_cases hji : j = c
      · subst hji
        simp
      · have ho : s.onDelay j = true := by simpa [hji] using hj
        simpa [hji] using h.delay_blocked j ho

theorem block_inv (s : Sched n) (h : Inv s) (p : Policy) : Inv (block s p) :=
  dispatch_inv (blockCurrent s 0 false) (blockCurrent_inv s h 0 false) p

theorem exitCurrent_inv (s : Sched n) (h : Inv s) : Inv (exitCurrent s) := by
  cases hc : s.current with
  | none =>
    simp [exitCurrent, hc]
    exact h
  | some c =>
    have halive : s.park c = .alive := h.current_alive c hc
    simp [exitCurrent, hc]
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · exact h.ready_nodup.erase c
    · intro i hi; simp at hi
    · intro i hi; simp at hi
    · intro j hj
      have hne : j ≠ c := by
        intro heq
        simp [heq] at hj
      have hj' : s.park j = .alive := by simpa [hne] using hj
      have hlive := h.alive_live j hj'
      cases hlive with
      | inl hm =>
        exact Or.inl ((h.ready_nodup.mem_erase_iff).2 ⟨hne, hm⟩)
      | inr hcur =>
        have heq : j = c := by
          exact (by simpa [hc] using hcur : c = j).symm
        exact absurd heq hne
    · intro j hj
      have hne : j ≠ c := by
        intro heq
        simp [heq, halive] at hj
      have hj' : s.park j = .blocked := by simpa [hne] using hj
      have ⟨hnr, _⟩ := h.blocked_idle j hj'
      refine ⟨?_, by simp⟩
      intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 hm).2
    · intro j hj
      have hne : j ≠ c := by
        intro heq
        simp [heq, halive] at hj
      have hj' : s.park j = .unused := by simpa [hne] using hj
      have ⟨hnr, _⟩ := h.unused_idle j hj'
      refine ⟨?_, by simp⟩
      intro hm
      exact hnr ((h.ready_nodup.mem_erase_iff).1 hm).2
    · intro j hj
      by_cases hji : j = c
      · subst hji
        refine ⟨h.ready_nodup.not_mem_erase, by simp⟩
      · have hj' : s.park j = .terminated := by simpa [hji] using hj
        have ⟨hnr, _⟩ := h.terminated_idle j hj'
        refine ⟨?_, by simp⟩
        intro hm
        exact hnr ((h.ready_nodup.mem_erase_iff).1 hm).2
    · intro j hj
      by_cases hji : j = c
      · simp [hji] at hj
      · have ho : s.onDelay j = true := by simpa [hji] using hj
        simpa [hji] using h.delay_blocked j ho

theorem exit_inv (s : Sched n) (h : Inv s) (p : Policy) : Inv (exitTask s p) :=
  dispatch_inv (exitCurrent s) (exitCurrent_inv s h) p

theorem unblock_inv (s : Sched n) (h : Inv s) (p : Policy) (i : Fin n) :
    Inv (unblock s p i) := by
  unfold unblock
  split
  · rename_i hb
    have hpark : s.park i = .blocked := (beq_iff_eq).1 hb
    have hidle := h.blocked_idle i hpark
    exact dispatch_inv _ (promote_inv s h i hidle) p
  · exact h

theorem delay_inv (s : Sched n) (h : Inv s) (p : Policy) (dt : Nat) : Inv (delay s p dt) := by
  unfold delay
  split
  · exact yield_inv s h p
  · exact dispatch_inv _ (blockCurrent_inv s h (s.now + dt) true) p

theorem wakeOne_inv (s : Sched n) (h : Inv s) (i : Fin n) : Inv (wakeOne s i) := by
  unfold wakeOne
  split
  · rename_i hd
    simp [due, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hd
    have hpark : s.park i = .blocked := hd.1.1
    exact promote_inv s h i (h.blocked_idle i hpark)
  · exact h

theorem wakeDue_inv (s : Sched n) (h : Inv s) : Inv (wakeDue s) := by
  unfold wakeDue
  suffices ∀ (ts : List (Fin n)) (acc : Sched n), Inv acc →
      Inv (ts.foldl (fun acc i => wakeOne acc i) acc) by
    exact this (List.finRange n) s h
  intro ts
  induction ts with
  | nil =>
    intro acc hacc
    simpa using hacc
  | cons i ts ih =>
    intro acc hacc
    simp
    exact ih (wakeOne acc i) (wakeOne_inv acc hacc i)

theorem now_inv (s : Sched n) (h : Inv s) (t : Nat) : Inv { s with now := t } := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simpa using h.ready_nodup
  · simpa using h.current_not_ready
  · simpa using h.current_alive
  · simpa using h.alive_live
  · simpa using h.blocked_idle
  · simpa using h.unused_idle
  · simpa using h.terminated_idle
  · simpa using h.delay_blocked

theorem tick_inv (s : Sched n) (h : Inv s) (p : Policy) : Inv (tick s p) := by
  unfold tick
  exact dispatch_inv _ (wakeDue_inv _ (now_inv s h (s.now + 1))) p

theorem wakeOne_keeps (s : Sched n) (i j : Fin n)
    (hp : s.park j = .blocked) (ho : s.onDelay j = true) (hd : s.now < s.deadline j) :
    (wakeOne s i).park j = .blocked ∧ (wakeOne s i).onDelay j = true ∧
      (wakeOne s i).deadline j = s.deadline j ∧ (wakeOne s i).now = s.now := by
  unfold wakeOne
  split
  · rename_i hdue
    by_cases hij : i = j
    · subst hij
      simp [due, hp, ho, decide_eq_true_eq] at hdue
      omega
    · have hji : j ≠ i := fun h => hij h.symm
      simp [promote, hji, hp, ho]
  · simp [hp, ho]

theorem wakeDue_keeps (s : Sched n) (j : Fin n)
    (hp : s.park j = .blocked) (ho : s.onDelay j = true) (hd : s.now < s.deadline j) :
    (wakeDue s).park j = .blocked ∧ (wakeDue s).onDelay j = true ∧
      (wakeDue s).deadline j = s.deadline j ∧ (wakeDue s).now = s.now := by
  unfold wakeDue
  suffices ∀ (ts : List (Fin n)) (acc : Sched n),
      acc.park j = .blocked → acc.onDelay j = true → acc.now < acc.deadline j →
      acc.deadline j = s.deadline j → acc.now = s.now →
      (ts.foldl (fun acc i => wakeOne acc i) acc).park j = .blocked ∧
      (ts.foldl (fun acc i => wakeOne acc i) acc).onDelay j = true ∧
      (ts.foldl (fun acc i => wakeOne acc i) acc).deadline j = s.deadline j ∧
      (ts.foldl (fun acc i => wakeOne acc i) acc).now = s.now by
    exact this (List.finRange n) s hp ho hd rfl rfl
  intro ts
  induction ts with
  | nil =>
    intro acc hp' ho' _ hd' hn'
    simp [hp', ho', hd', hn']
  | cons i ts ih =>
    intro acc hp' ho' hd' hdead hn'
    simp
    have hk := wakeOne_keeps acc i j hp' ho' hd'
    exact ih (wakeOne acc i) hk.1 hk.2.1
      (by simpa [hk.2.2.1, hk.2.2.2] using hd')
      (by simpa [hk.2.2.1] using hdead)
      (by simpa [hk.2.2.2] using hn')

theorem tick_keeps_early (s : Sched n) (h : Inv s) (p : Policy) (i : Fin n)
    (hp : s.park i = .blocked) (ho : s.onDelay i = true) (hearly : s.now + 1 < s.deadline i) :
    let s' := tick s p
    Inv s' ∧ s'.park i = .blocked ∧ s'.onDelay i = true ∧ s'.deadline i = s.deadline i ∧
      s'.now = s.now + 1 ∧ s'.current ≠ some i := by
  let s1 : Sched n := { s with now := s.now + 1 }
  have h1 : Inv s1 := now_inv s h (s.now + 1)
  have hearly1 : s1.now < s1.deadline i := by
    simpa [s1] using hearly
  have hpark1 : s1.park i = .blocked := by simpa [s1] using hp
  have hon1 : s1.onDelay i = true := by simpa [s1] using ho
  have hw := wakeDue_keeps s1 i hpark1 hon1 hearly1
  have hinvw : Inv (wakeDue s1) := wakeDue_inv s1 h1
  have hnotcur : (wakeDue s1).current ≠ some i := by
    have := (hinvw.blocked_idle i hw.1).2
    exact this
  have hnotready : i ∉ (wakeDue s1).ready := (hinvw.blocked_idle i hw.1).1
  have hch : choose (wakeDue s1) p ≠ some i := choose_not (wakeDue s1) hinvw p i hnotcur hnotready
  have hcur : (dispatch (wakeDue s1) p).current ≠ some i := by
    have hdis := applyChoice_current (wakeDue s1) (choose (wakeDue s1) p)
    simp [dispatch] at hdis ⊢
    cases hdis with
    | inl h =>
      intro hc
      exact hnotcur (by simpa [h] using hc)
    | inr h =>
      intro hc
      exact hch (by simpa [h] using hc)
  have hf := dispatch_same_fields (wakeDue s1) p i
  refine ⟨dispatch_inv (wakeDue s1) hinvw p, ?_, ?_, ?_, ?_, hcur⟩
  · simpa [tick, s1] using (by simpa [hf.1] using hw.1 : (dispatch (wakeDue s1) p).park i = .blocked)
  · simpa [tick, s1] using (by simpa [hf.2.1] using hw.2.1 :
      (dispatch (wakeDue s1) p).onDelay i = true)
  · have hdead : (wakeDue s1).deadline i = s.deadline i := by simpa [s1] using hw.2.2.1
    simpa [tick, s1] using (by simpa [hf.2.2.1] using hdead :
      (dispatch (wakeDue s1) p).deadline i = s.deadline i)
  · have hnow : (wakeDue s1).now = s.now + 1 := by simpa [s1] using hw.2.2.2
    simpa [tick, s1] using (by simpa [hf.2.2.2] using hnow :
      (dispatch (wakeDue s1) p).now = s.now + 1)

/-- After `k` ticks, a task whose deadline is still ahead is blocked. -/
theorem ticks_before_deadline (s : Sched n) (h : Inv s) (p : Policy) (i : Fin n)
    (hp : s.park i = .blocked) (ho : s.onDelay i = true) (k : Nat)
    (hearly : s.now + k < s.deadline i) :
    Inv (afterTicks s p k) ∧ (afterTicks s p k).park i = .blocked ∧
      (afterTicks s p k).onDelay i = true ∧ (afterTicks s p k).now = s.now + k ∧
      phase (afterTicks s p k) i = .blocked := by
  induction k generalizing s h hp ho with
  | zero =>
    -- `now = now + 0` simplifies to `True`, so the conjunction has four fields.
    simp [afterTicks]
    exact And.intro h (And.intro hp (And.intro ho ((phase_blocked_iff s h i).2 hp)))
  | succ k ih =>
    have hstep : s.now + 1 < s.deadline i := by omega
    have ht := tick_keeps_early s h p i hp ho hstep
    have hrest : (tick s p).now + k < (tick s p).deadline i := by
      have hnow := ht.2.2.2.2.1
      have hdead := ht.2.2.2.1
      omega
    have ih' := ih (tick s p) ht.1 ht.2.1 ht.2.2.1 hrest
    have hphase : phase (afterTicks (tick s p) p k) i = .blocked := ih'.2.2.2.2
    refine ⟨?_, ?_, ?_, ?_, hphase⟩
    · simpa [afterTicks] using ih'.1
    · simpa [afterTicks] using ih'.2.1
    · simpa [afterTicks] using ih'.2.2.1
    · have hnow := ih'.2.2.2.1
      simp [afterTicks] at hnow ⊢
      omega

theorem delay_blocks (s : Sched n) (h : Inv s) (p : Policy) (c : Fin n)
    (hc : s.current = some c) (dt : Nat) (hdt : dt ≠ 0) :
    let s' := delay s p dt
    Inv s' ∧ s'.park c = .blocked ∧ s'.onDelay c = true ∧ s'.deadline c = s.now + dt ∧
      s'.now = s.now ∧ s'.current ≠ some c := by
  unfold delay
  have hnz : (dt == 0) = false := by simp [hdt]
  simp [hdt]
  have hb := blockCurrent_inv s h (s.now + dt) true
  have heq := blockCurrent_eq s c (s.now + dt) true hc
  have hpark : (blockCurrent s (s.now + dt) true).park c = .blocked := by
    simp [heq]
  have hon : (blockCurrent s (s.now + dt) true).onDelay c = true := by
    simp [heq]
  have hdead : (blockCurrent s (s.now + dt) true).deadline c = s.now + dt := by
    simp [heq]
  have hnow : (blockCurrent s (s.now + dt) true).now = s.now := by
    simp [heq]
  have hcur0 : (blockCurrent s (s.now + dt) true).current = none := by
    simp [heq]
  have hnotready : c ∉ (blockCurrent s (s.now + dt) true).ready :=
    (hb.blocked_idle c hpark).1
  have hnotcur : (blockCurrent s (s.now + dt) true).current ≠ some c := by
    simp [hcur0]
  have hch := choose_not _ hb p c hnotcur hnotready
  have hf := dispatch_same_fields (blockCurrent s (s.now + dt) true) p c
  have hcur : (dispatch (blockCurrent s (s.now + dt) true) p).current ≠ some c := by
    have hdis := applyChoice_current (blockCurrent s (s.now + dt) true)
      (choose (blockCurrent s (s.now + dt) true) p)
    simp [dispatch] at hdis ⊢
    cases hdis with
    | inl h =>
      intro hc'
      exact hnotcur (by simpa [h] using hc')
    | inr h =>
      intro hc'
      exact hch (by simpa [h] using hc')
  refine ⟨dispatch_inv _ hb p, ?_, ?_, ?_, ?_, hcur⟩
  · simpa [hf.1] using hpark
  · simpa [hf.2.1] using hon
  · simpa [hf.2.2.1] using hdead
  · simpa [hf.2.2.2] using hnow

theorem coop_yield_runs_head (s : Sched n) (h : Inv s) (c i : Fin n) (rest : List (Fin n))
    (hc : s.current = some c) (hr : s.ready = i :: rest) :
    (yieldTask s .cooperative).current = some i := by
  have hnot : c ∉ s.ready := h.current_not_ready c hc
  have hpush : readyPush s.ready c = s.ready ++ [c] := readyPush_of_not_mem hnot
  simp [yieldTask, hc, dispatch]
  have hc1 : (demoteOf s c).current = none := by simp [demoteOf]
  have hr1 : (demoteOf s c).ready = i :: (rest ++ [c]) := by
    simp [demoteOf]
    rw [hpush, hr]
    simp
  have hch : choose (demoteOf s c) .cooperative = some i := by
    simp [choose, hc1, hr1]
  simp [hch, applyChoice, hc1, activate]

theorem priority_max (s : Sched n) (h : Inv s) : priorityMax (dispatch s .priority) := by
  intro c hc i hready
  have hinv := dispatch_inv s h .priority
  have himem : i ∈ (dispatch s .priority).ready := (phase_ready_iff _ hinv i).1 hready
  have hp := dispatch_same_fields s .priority
  cases hm : pickMax s s.ready with
  | none =>
    have hempty : s.ready = [] := pickMax_none s s.ready hm
    have hch : choose s .priority = s.current := by simp [choose, hm]
    have hs : dispatch s .priority = s := by
      cases hcur : s.current with
      | none => simp [dispatch, hch, hcur, applyChoice]
      | some cur => simp [dispatch, hch, hcur, applyChoice]
    simp [hs, hempty] at himem
  | some m =>
    have ⟨hmmem, hmax⟩ := pickMax_some s s.ready m hm
    cases hcur : s.current with
    | none =>
      have hch : choose s .priority = some m := by simp [choose, hm, hcur]
      have hdis : dispatch s .priority = activate s m := by simp [dispatch, hch, applyChoice, hcur]
      have hc' : c = m := by
        have hsj : some m = some c := by simpa [hdis, activate] using hc
        injection hsj with hsj
        exact hsj.symm
      have hine : i ≠ m := by
        intro heq
        have hnot := h.ready_nodup.not_mem_erase (a := m)
        simp [hdis, activate, heq] at himem
        exact hnot himem
      have hpri : s.prio i ≤ s.prio m := by
        have him : i ∈ s.ready := (h.ready_nodup.mem_erase_iff).1
          (by simpa [hdis, activate] using himem) |>.2
        exact hmax i him
      have hpc : (dispatch s .priority).prio i = s.prio i := (hp i).2.2.2.2
      have hpm : (dispatch s .priority).prio c = s.prio m := by simpa [hc'] using (hp c).2.2.2.2
      simpa [hpc, hpm] using hpri
    | some cur =>
      by_cases hgt : s.prio m > s.prio cur
      · have hch : choose s .priority = some m := by simp [choose, hm, hcur, hgt]
        have hne : cur ≠ m := by
          intro heq
          exact h.current_not_ready m (heq ▸ hcur) hmmem
        have hdis : dispatch s .priority = activate (demoteOf s cur) m := by
          simp [dispatch, hch, applyChoice, hcur, hne]
        have hc' : c = m := by
          have hsj : some m = some c := by simpa [hdis, activate] using hc
          injection hsj with hsj
          exact hsj.symm
        have hready0 : (demoteOf s cur).ready = s.ready ++ [cur] := by
          simp [demoteOf, readyPush_of_not_mem (h.current_not_ready cur hcur)]
        have hine : i ≠ m := by
          intro heq
          have hnodup : (demoteOf s cur).ready.Nodup :=
            (demote_inv s h cur hcur).ready_nodup
          have hnot := hnodup.not_mem_erase (a := m)
          simp [hdis, activate, heq] at himem
          exact hnot himem
        have him : i ∈ s.ready ++ [cur] := by
          have hnodup : (demoteOf s cur).ready.Nodup :=
            (demote_inv s h cur hcur).ready_nodup
          have := (hnodup.mem_erase_iff).1 (by simpa [hdis, activate] using himem)
          simpa [hready0] using this.2
        have hpri : s.prio i ≤ s.prio m := by
          have him' := List.mem_append.1 him
          cases him' with
          | inl hr => exact hmax i hr
          | inr hc'' =>
            simp at hc''
            subst hc''
            exact Nat.le_of_lt hgt
        have hpc : (dispatch s .priority).prio i = s.prio i := (hp i).2.2.2.2
        have hpm : (dispatch s .priority).prio c = s.prio m := by simpa [hc'] using (hp c).2.2.2.2
        simpa [hpc, hpm] using hpri
      · have hle : s.prio m ≤ s.prio cur := Nat.le_of_not_lt hgt
        have hch : choose s .priority = some cur := by simp [choose, hm, hcur, hgt]
        have hdis : dispatch s .priority = s := by simp [dispatch, hch, applyChoice, hcur]
        have hc' : c = cur := by
          exact (by simpa [hdis, hcur] using hc : cur = c).symm
        have him : i ∈ s.ready := by simpa [hdis] using himem
        have hpri : s.prio i ≤ s.prio cur := Nat.le_trans (hmax i him) hle
        simpa [hdis, hc'] using hpri

end Vos.Sched
