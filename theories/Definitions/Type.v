Require Import Nat.
Require Import List.
Require Import Definitions.Ident.

Require Import ssreflect ssrfun ssrbool.

Declare Scope system_t_type_scope.
Open Scope system_t_type_scope.

Module TIdent <: IDENT := NatIdent.

Module TSet := NatSet.

Module TSetFacts.

  Include FSets.FSetFacts.Facts TSet.

  Include FSets.FSetProperties.Properties TSet.

  Include FSets.FSetDecide.Decide TSet.

End TSetFacts.

Module TMap := NatMap.

Module TMapFacts := FSets.FMapFacts.Facts TMap.

Module TIdentFacts := IdentFacts TIdent TSet TMap.

(** System T types. *)

Inductive typeT :=
  | natT : typeT
  | boolT : typeT
  | tvarT : TIdent.t -> typeT
  | funT : typeT -> typeT -> typeT
  | prodT : typeT -> typeT -> typeT.

Notation "t ->T u" := (funT t u) (at level 35, right associativity) : system_t_type_scope.

Notation "t *T u" := (prodT t u) (at level 34, left associativity) : system_t_type_scope.

(** Substitution of a type variable. 
*)
Fixpoint tsubst (x : TIdent.t) (a t : typeT) :=
  match t with
  | tvarT y =>
    match TIdentFacts.eqb x y with
    | true => a
    | _ => tvarT y
    end
  | funT t u =>
    funT (tsubst x a t) (tsubst x a u)
  | prodT t u =>
    prodT (tsubst x a t) (tsubst x a u)
  | _ =>
    t
  end.

Notation "u (| x |-> t |)" := (tsubst x t u) (at level 45) :
    system_t_type_scope.

(** Parallel substitution of a type variable. 
*)
Fixpoint par_tsubst (s : TMap.t typeT) (t : typeT) :=
  match t with
  | tvarT x =>
    match TMap.find x s with
    | Some a => a
    | _ => tvarT x
    end
  | funT t u =>
    funT (par_tsubst s t) (par_tsubst s u)
  | prodT t u =>
    prodT (par_tsubst s t) (par_tsubst s u)
  | _ =>
    t
  end.

Notation "x >> s" := (par_tsubst s x) (at level 45) : system_t_type_scope.

(** Composition of two maps. Specification is in [Theorems.Type.v].
*)
Definition tsubst_compose (r s : TMap.t typeT) : TMap.t typeT :=
  TMap.map2
    (fun opt1 opt2 =>
      match opt1, opt2 with
      | Some t, _ => Some (t >> s)
      | _, Some t => Some t
      | _, _ => None end)
    r s.

Notation "r >>> s" :=
  (tsubst_compose r s) (at level 40, left associativity) :
    system_t_type_scope.

(** Composition with a single variable substitution, both left and right
versions.
*)
Definition tsubst_add_l (x : TIdent.t) (t : typeT) (s : TMap.t typeT) :
    TMap.t typeT :=
  match TMap.find x s with
  | None => TMap.add x t (TMap.map (tsubst x t) s)
  | _ => TMap.map (tsubst x t) s
  end.

Definition tsubst_add_r (x : TIdent.t) (t : typeT) (s : TMap.t typeT) :
    TMap.t typeT :=
  TMap.add x (t >> s) s.

Notation "(| x |-> t |) >>> s" := (tsubst_add_r x t s) (at level 30) : system_t_type_scope.

(** Extensionnal equality for maps, viewed as the function they induce
    by parallel substitution.
*)
Definition ext_equal (r s : TMap.t typeT) : Prop :=
  forall t : typeT, t >> r = t >> s. 

Notation "r >>= s" := (ext_equal r s) (at level 50) :
    system_t_type_scope.

(** Substitution order.
*)
Definition tsubst_order_with_tsubst (q r s : TMap.t typeT) : Prop :=
  s >>= r >>> q.

Definition tsubst_order (r s : TMap.t typeT) : Prop :=
  exists q : TMap.t typeT, s >>= r >>> q.

Notation "r >>< s" := (tsubst_order r s) (at level 50) :
    system_t_type_scope.

Definition typeT_order (t u : typeT) : Prop :=
  exists s : TMap.t typeT, u = t >> s.

Notation "t >><t u" :=
  (typeT_order t u) (at level 50) : system_t_type_scope.

(** A unification problem is a list of pairs of types.
    We are interested in finding maps [s] that solve it,
    i.e. such that for every pair [(t, u)]
    we have [t >> s = u >> s].
*)
Definition unification_problem : Type := list (typeT * typeT).

Fixpoint variable_set (t : typeT) :=
  match t with
  | tvarT x => TSet.singleton x
  | t ->T u
  | t *T u =>
    TSet.union (variable_set t) (variable_set u)
  | _ =>
    TSet.empty
  end.

Fixpoint occurs (x : TIdent.t) (t : typeT) : bool :=
  match t with
  | tvarT y => TIdentFacts.eqb x y
  | t ->T u 
  | t *T u => occurs x t || occurs x u
  | _ => false
  end.

Fixpoint size (t : typeT) : nat :=
  match t with
  | t ->T u 
  | t *T u => S (size t + size u)
  | _ => S O
  end.

Fixpoint problem_size (p : unification_problem) : nat :=
  match p with
  | nil => O
  | ((t, u) :: p)%list => size t + size u + problem_size p
  end.

Fixpoint problem_variable_set (p : unification_problem) : TSet.t :=
  match p with
  | nil => TSet.empty
  | ((t, u) :: p)%list =>
    TSet.union
      (TSet.union (variable_set t) (variable_set u))
      (problem_variable_set p)
  end.

Inductive unification_problem_order (p q : unification_problem) : Prop :=
  | card_lt :
    TSet.cardinal (problem_variable_set p) <
    TSet.cardinal (problem_variable_set q) ->
    unification_problem_order p q
  | card_le_size_lt :
    TSet.cardinal (problem_variable_set p) <=
    TSet.cardinal (problem_variable_set q) ->
    problem_size p < problem_size q ->
    unification_problem_order p q.

Inductive result (A B : Type) : Type :=
  | ok : A -> result A B
  | err : B -> result A B.

Arguments ok {A B} _.
Arguments err {A B} _.

Definition result_map {A B C : Type} (f : A -> B) (r : result A C) :
    result B C :=
  match r with
  | ok a => ok (f a)
  | err b => err b
  end.

Variant unification_error : Type :=
  | unification_error_different_constructors :
    typeT -> typeT -> unification_error
  | unification_error_tvarT_occurs :
    TIdent.t -> typeT -> unification_error.

Definition unifies (s : TMap.t typeT) (t u : typeT) : Prop :=
  t >> s = u >> s.

Definition solves
  (s : TMap.t typeT) (p : unification_problem) : Prop :=
    List.Forall (fun c => unifies s (fst c) (snd c)) p.

Definition unification_problem_tsubst
  (x : TIdent.t) (t : typeT) (p : unification_problem) :
    unification_problem :=
  map (fun c : typeT * typeT => (c.1 (|x |-> t|), c.2 (|x |-> t|))) p.
