
open HolKernel Parse boolLib bossLib;

val _ = new_theory "hol_verification";

open hol_kernelTheory model_syntaxTheory;
open listTheory arithmeticTheory combinTheory pairTheory;

open monadsyntax;
val _ = temp_overload_on ("monad_bind", ``ex_bind``);
val _ = temp_overload_on ("return", ``ex_return``);
val _ = set_trace "Unicode" 0;

infix \\ val op \\ = op THEN;

(* ------------------------------------------------------------------------- *)
(* Translations from implementation types to model types.                    *)
(* ------------------------------------------------------------------------- *)

val MEM_hol_type_size = prove(
  ``!tys a. MEM a tys ==> hol_type_size a < hol_type1_size tys``,
  Induct \\ SIMP_TAC std_ss [MEM,hol_type_size_def] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [] \\ RES_TAC \\ FULL_SIMP_TAC std_ss [] \\ DECIDE_TAC);

val hol_ty_def = tDefine "hol_ty" `
  (hol_ty (hol_kernel$Tyvar v) = Tyvar v) /\
  (hol_ty (Tyapp s tys) =
     if (s = "bool") /\ (tys = []) then Bool else
     if (s = "ind") /\ (tys = []) then Ind else
     if (s = "fun") /\ (LENGTH tys = 2) then
       Fun (hol_ty (EL 0 tys)) (hol_ty (EL 1 tys))
     else Tyapp s (MAP hol_ty tys))`
 (WF_REL_TAC `measure hol_type_size`
  \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC MEM_hol_type_size \\ TRY DECIDE_TAC
  \\ Cases_on `tys` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Cases_on `t` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Cases_on `t'` \\ FULL_SIMP_TAC (srw_ss()) [hol_type_size_def]
  \\ DECIDE_TAC);

val _ = temp_overload_on("fun",``\x y. hol_kernel$Tyapp "fun" [x;y]``);
val _ = temp_overload_on("bool_ty",``hol_kernel$Tyapp "bool" []``);
val _ = temp_overload_on("impossible_term",``Const "=" Ind``);

val hol_tm_def = Define `
  (hol_tm (Var v ty) = Var v (hol_ty ty)) /\
  (hol_tm (Const s ty) =
     if s = "=" then
       if (?a. ty = fun a (fun a bool_ty))
       then Equal (domain (hol_ty ty))
       else impossible_term
     else
     if s = "@" then
       if (?a. ty = fun (fun a bool_ty) a)
       then Select (codomain (hol_ty ty))
       else impossible_term
     else
       Const s (hol_ty ty)) /\
  (hol_tm (Comb x y) = Comb (hol_tm x) (hol_tm y)) /\
  (hol_tm (Abs (Var v ty) x) = Abs v (hol_ty ty) (hol_tm x)) /\
  (hol_tm _ = impossible_term)`;

val hol_defs_def = Define `
  (hol_defs [] = []) /\
  (hol_defs (Axiomdef tm::defs) =
    (Axiomdef (hol_tm tm)) :: hol_defs defs) /\
  (hol_defs (Constdef n tm::defs) =
    (Constdef n (hol_tm tm)) :: hol_defs defs) /\
  (hol_defs (Typedef s1 tm s2 s3 :: defs) =
    (Typedef s1 (hol_tm tm) s2 s3) :: hol_defs defs)`;

(* ------------------------------------------------------------------------- *)
(* type_ok, term_ok, context_ok and |- for implementation types.             *)
(* ------------------------------------------------------------------------- *)

val TYPE_def = Define `
  TYPE defs ty = type_ok (hol_defs defs) (hol_ty ty)`;

val TERM_def = Define `
  TERM defs tm = welltyped_in (hol_tm tm) (hol_defs defs)`;

val CONTEXT_def = Define `
  CONTEXT defs = context_ok (hol_defs defs)`;

val THM_def = Define `
  THM defs (Sequent asl c) = ((hol_defs defs, MAP hol_tm asl) |- hol_tm c)`;

(* ------------------------------------------------------------------------- *)
(* State invariant - types/terms/axioms can be extracted from defs           *)
(* ------------------------------------------------------------------------- *)

val _ = temp_overload_on("aty",``(Tyvar "A"):hol_type``);

val STATE_def = Define `
  STATE state defs =
    let hds = hol_defs defs in
      (defs = state.the_definitions) /\ context_ok hds /\
      (state.the_type_constants = types hds ++ [("bool",0);("ind",0);("fun",2)]) /\
      ALL_DISTINCT (MAP FST state.the_type_constants) /\
      ALL_DISTINCT (MAP FST state.the_term_constants) /\
      TERM defs state.the_clash_var /\
      ?user_defined.
        (state.the_term_constants = user_defined ++
                     [("=",fun aty (fun aty bool_ty));
                      ("@",fun (fun aty bool_ty) aty)]) /\
        (consts hds = MAP (\(name,ty). (name, hol_ty ty)) user_defined)`;

(* ------------------------------------------------------------------------- *)
(* Certain terms cannot occur                                                *)
(* ------------------------------------------------------------------------- *)

val NOT_EQ_CONST = prove(
  ``!defs x. context_ok (hol_defs defs) ==>
             ~MEM ("=",x) (consts (hol_defs defs))``,
  Induct \\ FULL_SIMP_TAC std_ss [consts,MAP,FLAT,MEM,hol_defs_def]
  \\ Cases \\ FULL_SIMP_TAC std_ss [consts,MAP,FLAT,MEM,hol_defs_def]
  \\ FULL_SIMP_TAC std_ss [consts_aux,APPEND,MEM,context_ok,def_ok]
  \\ FULL_SIMP_TAC std_ss [reserved_const_names,MEM]);

val impossible_term_thm = prove(
  ``TERM defs tm ==> hol_tm tm <> impossible_term ``,
  SIMP_TAC std_ss [TERM_def,welltyped_in] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [term_ok] \\ IMP_RES_TAC NOT_EQ_CONST);

val Abs_Var = prove(
  ``TERM defs (Abs v tm) ==> ?s ty. v = Var s ty``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC impossible_term_thm
  \\ Cases_on `v` \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]);

val Select_type = prove(
  ``TERM defs (Const "@" ty) ==> ?a. ty = fun (fun a bool_ty) a``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC impossible_term_thm
  \\ FULL_SIMP_TAC std_ss [hol_tm_def,EVAL ``"@" = "="``] \\ METIS_TAC []);

val Equal_type = prove(
  ``TERM defs (Const "=" ty) ==> ?a. ty = fun a (fun a bool_ty)``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC impossible_term_thm
  \\ FULL_SIMP_TAC std_ss [hol_tm_def] \\ METIS_TAC []);

val Equal_type_IMP = prove(
  ``TERM defs (Comb (Const "=" (fun a' (fun a' bool_ty))) ll) ==>
    (typeof (hol_tm ll) = (hol_ty a'))``,
  SIMP_TAC (srw_ss()) [TERM_def,welltyped_in,hol_tm_def,hol_ty_def,
    WELLTYPED_CLAUSES,domain,typeof,type_INJ]);

(* ------------------------------------------------------------------------- *)
(* TYPE and TERM lemmas                                                      *)
(* ------------------------------------------------------------------------- *)

val LENGTH_EQ_2 = prove(
  ``!l. (LENGTH l = 2) = ?x1 x2. l = [x1;x2]``,
  Cases \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Cases_on `t` \\ FULL_SIMP_TAC (srw_ss()) [LENGTH_NIL]);

val TYPE = prove(
  ``(TYPE defs (Tyvar v)) /\
    (TYPE defs (Tyapp op tys) ==> EVERY (TYPE defs) tys)``,
  REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [TYPE_def,hol_ty_def,EVERY_MEM]
  THEN1 (ONCE_REWRITE_TAC [type_ok_CASES] \\ SIMP_TAC std_ss [type_INJ])
  \\ POP_ASSUM MP_TAC \\ SRW_TAC [] []
  \\ REPEAT (POP_ASSUM MP_TAC) THEN1
   (SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_DISTINCT,type_INJ]
    \\ Cases_on `tys` \\ FULL_SIMP_TAC std_ss [LENGTH]
    \\ Cases_on `t` \\ FULL_SIMP_TAC std_ss [LENGTH]
    \\ Q.SPEC_TAC (`t'`,`t'`)
    \\ FULL_SIMP_TAC (srw_ss()) [LENGTH_NIL,EL,HD]
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [])
  \\ SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_DISTINCT,type_INJ]
  \\ SIMP_TAC std_ss [MEM_MAP,PULL_EXISTS]);

val BASIC_TYPE = prove(
  ``(TYPE defs (fun ty1 ty2) = TYPE defs ty1 /\ TYPE defs ty2) /\
    (TYPE defs bool_ty)``,
  FULL_SIMP_TAC (srw_ss()) [TYPE_def,hol_ty_def] \\ REPEAT STRIP_TAC
  \\ SIMP_TAC std_ss [Once type_ok_CASES,type_DISTINCT,type_INJ]);

val TERM = prove(
  ``(TERM defs (Var n ty) ==> TYPE defs ty) /\
    (TERM defs (Const n ty) ==> TYPE defs ty) /\
    (TERM defs (Abs (Var v ty) x) ==> TERM defs x /\ TYPE defs ty) /\
    (TERM defs (Comb x y) ==> TERM defs x /\ TERM defs y)``,
  REPEAT CONJ_TAC THEN1
   (SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED,typeof,TYPE_def]
    \\ SIMP_TAC std_ss [term_ok])
  THEN1
   (Cases_on `n = "="` THEN1
      (FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
       \\ IMP_RES_TAC Equal_type \\ FULL_SIMP_TAC std_ss [BASIC_TYPE]
       \\ FULL_SIMP_TAC (srw_ss()) [TERM_def,welltyped_in,
            hol_tm_def,TYPE_def,hol_ty_def,
            METIS_PROVE [] ``(?a'. fun a (fun a bool_ty) = fun a'(fun a' bool_ty))``,
            WELLTYPED_CLAUSES,term_ok,domain])
    \\ Cases_on `n = "@"` THEN1
      (FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
       \\ IMP_RES_TAC Select_type \\ FULL_SIMP_TAC std_ss [BASIC_TYPE]
       \\ FULL_SIMP_TAC (srw_ss()) [TERM_def,welltyped_in,
            hol_tm_def,TYPE_def,hol_ty_def,
            METIS_PROVE [] ``(?a'. fun (fun a bool_ty) a = fun(fun a' bool_ty)a')``,
            WELLTYPED_CLAUSES,term_ok,domain,codomain])
    \\ ASM_SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED,
          typeof,TYPE_def,term_ok,term_DISTINCT])
  THEN1
   (SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED,typeof,TYPE_def]
    \\ SIMP_TAC (srw_ss()) [Once has_type_CASES,term_DISTINCT]
    \\ ASM_SIMP_TAC (srw_ss()) [term_INJ,type_INJ,term_ok])
  \\ SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED_CLAUSES]
  \\ ASM_SIMP_TAC std_ss [term_ok]);

val TYPE_LEMMA = prove(
  ``(STATE s defs /\ TYPE defs (Tyapp "bool" l) ==> (l = [])) /\
    (STATE s defs /\ TYPE defs (Tyapp "ind" l) ==> (l = [])) /\
    (STATE s defs /\ TYPE defs (Tyapp "fun" l) ==> ?x1 x2. l = [x1;x2])``,
  FULL_SIMP_TAC (srw_ss()) [TYPE_def,hol_ty_def] \\ SRW_TAC [] []
  \\ IMP_RES_TAC LENGTH_EQ_2 \\ FULL_SIMP_TAC std_ss [LENGTH,CONS_11]
  \\ REPEAT (POP_ASSUM MP_TAC)
  \\ ONCE_REWRITE_TAC [type_ok_CASES]
  \\ FULL_SIMP_TAC std_ss [type_DISTINCT,type_INJ]
  \\ FULL_SIMP_TAC std_ss [STATE_def,LET_DEF]
  \\ CCONTR_TAC
  \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss []
  \\ Q.PAT_ASSUM `s.the_type_constants = xxx` ASSUME_TAC
  \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT_APPEND,MAP_APPEND,MAP,
       MEM_MAP,PULL_EXISTS,MEM,FORALL_PROD]
  \\ RES_TAC \\ FULL_SIMP_TAC std_ss []
  \\ METIS_TAC []);

val type_IND = prove(
  ``!P. (!v. P (Tyvar v)) /\ (!op tys. EVERY P tys ==> P (Tyapp op tys)) ==>
        (!ty. P (ty:hol_type))``,
  REPEAT STRIP_TAC \\ completeInduct_on `hol_type_size ty`
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [PULL_FORALL]
  \\ Cases_on `ty` \\ FULL_SIMP_TAC std_ss []
  \\ Q.PAT_ASSUM `!op tys. bbb` MATCH_MP_TAC
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM] \\ REPEAT STRIP_TAC
  \\ Q.PAT_ASSUM `!x.bbb` MATCH_MP_TAC
  \\ POP_ASSUM MP_TAC \\ Q.SPEC_TAC (`e`,`e`) \\ Q.SPEC_TAC (`l`,`l`)
  \\ Induct \\ SIMP_TAC std_ss [MEM,hol_type_size_def]
  \\ REPEAT STRIP_TAC \\ RES_TAC
  \\ FULL_SIMP_TAC std_ss [hol_type_size_def] \\ DECIDE_TAC);

val MAP_EQ_MAP_IMP = prove(
  ``!xs ys f.
      (!x y. MEM x xs /\ MEM y ys /\ (f x = f y) ==> (x = y)) ==>
      (MAP f xs = MAP f ys) ==> (xs = ys)``,
  Induct \\ Cases_on `ys` \\ FULL_SIMP_TAC (srw_ss()) [MAP] \\ METIS_TAC []);

val TYPE_11 = prove(
  ``!x y. STATE s defs /\ TYPE defs x /\ TYPE defs y ==>
          ((hol_ty x = hol_ty y) = (x = y))``,
  HO_MATCH_MP_TAC type_IND \\ STRIP_TAC
  THEN1 (Cases_on `y` \\ SRW_TAC [] [type_INJ,type_DISTINCT,hol_ty_def])
  \\ FULL_SIMP_TAC std_ss [PULL_FORALL] \\ Cases_on `y`
  \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,type_INJ,type_DISTINCT]
  THEN1 SRW_TAC [] [type_INJ,type_DISTINCT]
  \\ REPEAT STRIP_TAC
  \\ Q.MATCH_ASSUM_RENAME_TAC `TYPE defs (Tyapp s2 l2)` []
  \\ POP_ASSUM MP_TAC
  \\ Q.MATCH_ASSUM_RENAME_TAC `TYPE defs (Tyapp s1 l1)` []
  \\ REPEAT STRIP_TAC
  \\ Cases_on `s1 = "bool"` THEN1
     (FULL_SIMP_TAC std_ss [hol_ty_def] \\ IMP_RES_TAC TYPE_LEMMA
      \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] [type_INJ,type_DISTINCT]
      \\ FULL_SIMP_TAC std_ss [])
  \\ Cases_on `s1 = "ind"` THEN1
     (FULL_SIMP_TAC std_ss [hol_ty_def] \\ IMP_RES_TAC TYPE_LEMMA
      \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] [type_INJ,type_DISTINCT]
      \\ FULL_SIMP_TAC std_ss [])
  \\ Cases_on `s1 = "fun"` THEN1
     (FULL_SIMP_TAC std_ss [hol_ty_def] \\ IMP_RES_TAC TYPE_LEMMA
      \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] [type_INJ,type_DISTINCT]
      \\ IMP_RES_TAC LENGTH_EQ_2 \\ FULL_SIMP_TAC (srw_ss()) []
      \\ FULL_SIMP_TAC std_ss [BASIC_TYPE]
      \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
      \\ CCONTR_TAC \\ FULL_SIMP_TAC std_ss [LENGTH])
  \\ FULL_SIMP_TAC std_ss []
  \\ SRW_TAC [] [type_INJ,type_DISTINCT]
  \\ IMP_RES_TAC TYPE
  \\ REPEAT (Q.PAT_ASSUM `~(bb /\ bbb)` (K ALL_TAC))
  \\ REPEAT STRIP_TAC \\ EQ_TAC \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM]
  \\ POP_ASSUM MP_TAC \\ MATCH_MP_TAC MAP_EQ_MAP_IMP
  \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC []);

val TERM_11 = prove(
  ``!x y. STATE s defs /\ TERM defs x /\ TERM defs y ==>
          ((hol_tm x = hol_tm y) = (x = y))``,
  Induct
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,term_INJ,term_DISTINCT]
  \\ REPEAT STRIP_TAC THEN1
   (Cases_on `y`
    \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,term_INJ,term_DISTINCT]
    \\ IMP_RES_TAC TERM THEN1 (METIS_TAC [TYPE_11])
    \\ SRW_TAC [] [term_DISTINCT]
    \\ IMP_RES_TAC Abs_Var \\ FULL_SIMP_TAC std_ss [hol_tm_def]
    \\ SRW_TAC [] [term_DISTINCT])
  THEN1
   (Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Const n h)` []
    \\ Cases_on `y`
    THEN1 (SRW_TAC [] [term_DISTINCT,hol_tm_def]) THEN1
     (SRW_TAC [] [term_DISTINCT,hol_tm_def,term_INJ,hol_ty_def,domain]
      \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss [BASIC_TYPE]
      \\ IMP_RES_TAC Equal_type \\ IMP_RES_TAC Select_type
      \\ FULL_SIMP_TAC (srw_ss()) [type_DISTINCT,type_INJ,codomain]
      \\ IMP_RES_TAC TYPE_11 \\ METIS_TAC [])
    \\ SRW_TAC [] [term_DISTINCT,hol_tm_def]
    \\ IMP_RES_TAC Abs_Var
    \\ SRW_TAC [] [term_DISTINCT,hol_tm_def])
  THEN1
   (Cases_on `y` \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ SRW_TAC [] [term_DISTINCT,hol_tm_def,term_INJ]
    \\ IMP_RES_TAC Abs_Var \\ SRW_TAC [] [term_DISTINCT,hol_tm_def])
  \\ Cases_on `y` \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
  \\ SRW_TAC [] [term_DISTINCT,hol_tm_def,term_INJ]
  \\ IMP_RES_TAC Abs_Var \\ SRW_TAC [] [term_DISTINCT,hol_tm_def,term_INJ]
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC TYPE_11 \\ METIS_TAC []);

(* ------------------------------------------------------------------------- *)
(* THM lemmas                                                                *)
(* ------------------------------------------------------------------------- *)

val type_INDUCT_ALT = prove(
  ``P Bool /\ P Ind /\ (!s xs. EVERY P xs ==> P (Tyapp s xs)) /\
    (!x y. P x /\ P y ==> P (Fun x y)) /\ (!v. P (Tyvar v)) ==>
    !x. P x``,
  STRIP_TAC \\ SUFF_TAC ``(!x. P (x:type)) /\ (!xs. EVERY P xs)``
  \\ FULL_SIMP_TAC std_ss []
  \\ HO_MATCH_MP_TAC type_INDUCT
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF]);

val type_ok_Fun = prove(
  ``type_ok defs (Fun ty1 ty2) = type_ok defs ty1 /\ type_ok defs ty2``,
  SIMP_TAC std_ss [Once type_ok_CASES,type_INJ,type_DISTINCT]);

val type_ok_Bool = prove(
  ``type_ok defs Bool``,
  SIMP_TAC std_ss [Once type_ok_CASES,type_INJ,type_DISTINCT]);

val type_ok_CONS = prove(
  ``!t defs d. type_ok defs t ==> type_ok (d::defs) t``,
  HO_MATCH_MP_TAC type_INDUCT_ALT \\ REPEAT STRIP_TAC
  \\ SIMP_TAC std_ss [Once type_ok_CASES,type_INJ,type_DISTINCT]
  \\ FULL_SIMP_TAC std_ss [type_ok_Fun,EVERY_MEM]
  \\ POP_ASSUM MP_TAC \\ SIMP_TAC std_ss [Once type_ok_CASES,type_INJ,type_DISTINCT]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [types,types_aux,FLAT,MAP,APPEND,MEM,MEM_APPEND]);

val term_ok_CONS = prove(
  ``!t defs d. term_ok defs t ==> term_ok (d::defs) t``,
  HO_MATCH_MP_TAC term_INDUCT \\ REPEAT STRIP_TAC
  \\ SIMP_TAC std_ss [Once term_ok,term_INJ,term_DISTINCT]
  \\ POP_ASSUM MP_TAC \\ SIMP_TAC std_ss [Once term_ok,term_INJ,term_DISTINCT]
  \\ FULL_SIMP_TAC std_ss [type_ok_CONS]
  \\ FULL_SIMP_TAC std_ss [consts,consts_aux,FLAT,MAP,APPEND,MEM,MEM_APPEND]
  \\ METIS_TAC [])

val welltyped_in_CONS = prove(
  ``!defs d t. welltyped_in t defs /\ def_ok d defs ==> welltyped_in t (d::defs)``,
  FULL_SIMP_TAC std_ss [welltyped_in,context_ok,term_ok_CONS])

val welltyped_in_Comb = prove(
  ``welltyped_in (Comb x y) defs = welltyped_in x defs /\ welltyped_in y defs /\
                                   welltyped (Comb x y)``,
  FULL_SIMP_TAC std_ss [welltyped_in,WELLTYPED_CLAUSES,term_ok] \\ METIS_TAC []);

val has_type_INJ = prove(
  ``!t ty1 ty2. has_type t ty1 /\ has_type t ty2 ==> (ty1 = ty2)``,
  HO_MATCH_MP_TAC term_INDUCT \\ REPEAT STRIP_TAC \\ NTAC 2 (POP_ASSUM MP_TAC)
  \\ SIMP_TAC std_ss [Once has_type_CASES] \\ STRIP_TAC
  \\ SIMP_TAC std_ss [Once has_type_CASES] \\ STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [term_INJ,term_DISTINCT] \\ RES_TAC
  \\ METIS_TAC [term_INJ,term_DISTINCT,type_INJ,type_DISTINCT]);

val term_ok_VSUBST = prove(
  ``!y ilist. term_ok defs y /\ EVERY (\(x,y). term_ok defs x) ilist ==>
        term_ok defs (VSUBST ilist y)``,
  HO_MATCH_MP_TAC term_INDUCT \\ SIMP_TAC std_ss [VSUBST,term_ok]
  \\ SRW_TAC [] [term_ok] THEN1
   (Induct_on `ilist`
    \\ FULL_SIMP_TAC std_ss [REV_ASSOCD,term_ok]
    \\ Cases \\ SRW_TAC [] [REV_ASSOCD,term_ok])
  \\ SRW_TAC [] [term_ok]
  \\ Q.PAT_ASSUM `!ii.bbb` MATCH_MP_TAC
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF,term_ok,EVERY_MEM,FORALL_PROD,
       MEM_FILTER,PULL_EXISTS] \\ REPEAT STRIP_TAC \\ RES_TAC);

val typeof_VSUBST = prove(
  ``welltyped rhs /\
     (!s s'.
        MEM (s',s) ilist ==>
        ?x ty. (s = Var x ty) /\ has_type s' ty) /\
    (typeof rhs = Bool) ==>
    (typeof (VSUBST ilist rhs) = Bool)``,
  REPEAT STRIP_TAC
  \\ IMP_RES_TAC VSUBST_WELLTYPED
  \\ FULL_SIMP_TAC std_ss [WELLTYPED]
  \\ IMP_RES_TAC VSUBST_HAS_TYPE
  \\ IMP_RES_TAC has_type_INJ);

val term_CASES = prove(
  ``(!a0 a1. P (Var a0 a1)) /\ (!a0 a1. P (Const a0 a1)) /\
    (!a. P (Equal a)) /\ (!a. P (Select a)) /\
    (!a0 a1. P (Comb a0 a1)) /\
    (!a0 a1 a2. P (Abs a0 a1 a2)) ==>
    !x. P x``,
  STRIP_TAC \\ HO_MATCH_MP_TAC term_INDUCT
  \\ FULL_SIMP_TAC std_ss []);

val IS_CLASH_IMP = prove(
  ``!x. IS_CLASH x ==> !tm. ~(x = Result tm)``,
  HO_MATCH_MP_TAC result_INDUCT
  \\ FULL_SIMP_TAC std_ss [result_DISTINCT,IS_CLASH]);

val NOT_IS_CLASH_IMP = prove(
  ``!x. ~IS_CLASH x ==> !tm. ~(x = Clash tm)``,
  HO_MATCH_MP_TAC result_INDUCT
  \\ FULL_SIMP_TAC std_ss [result_DISTINCT,IS_CLASH]);

val IS_RESULT_IMP = prove(
  ``!x. IS_RESULT x ==> (!tm. ~(x = Clash tm))``,
  HO_MATCH_MP_TAC result_INDUCT
  \\ FULL_SIMP_TAC std_ss [result_DISTINCT,IS_RESULT]);

val NOT_IS_RESULT_IMP_Clash = prove(
  ``!x. ~IS_RESULT x ==> ?var. x = Clash var``,
  HO_MATCH_MP_TAC result_INDUCT
  \\ FULL_SIMP_TAC std_ss [IS_RESULT,result_INJ]);

val IS_RESULT_IMP_Result = prove(
  ``!x. IS_RESULT x ==> ?res. x = Result res``,
  HO_MATCH_MP_TAC result_INDUCT
  \\ FULL_SIMP_TAC std_ss [IS_RESULT,result_INJ]);

val NOT_IS_CLASH_IMP_Result = prove(
  ``!x. ~IS_CLASH x ==> ?res. x = Result res``,
  HO_MATCH_MP_TAC result_INDUCT
  \\ FULL_SIMP_TAC std_ss [IS_CLASH,result_INJ]);

val type_ok_TYPE_SUBST = prove(
  ``(!s1 s2. MEM (s1,s2) tyin ==> type_ok defs s1) /\ type_ok defs a ==>
    type_ok defs (TYPE_SUBST tyin a)``,
  STRIP_TAC \\ POP_ASSUM MP_TAC \\ Q.SPEC_TAC (`a`,`a`)
  \\ HO_MATCH_MP_TAC type_INDUCT_ALT
  \\ SIMP_TAC std_ss [TYPE_SUBST] \\ REVERSE (REPEAT STRIP_TAC) THEN1
   (Induct_on `tyin` \\ FULL_SIMP_TAC std_ss [REV_ASSOCD]
    \\ Cases \\ FULL_SIMP_TAC std_ss [MEM,REV_ASSOCD] \\ METIS_TAC [])
  \\ POP_ASSUM MP_TAC
  \\ ONCE_REWRITE_TAC [type_ok_CASES]
  \\ SIMP_TAC std_ss [type_INJ,type_DISTINCT,LENGTH_MAP]
  \\ FULL_SIMP_TAC std_ss []
  \\ SIMP_TAC std_ss [MEM_MAP,PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM]);

val IMP_IMP = METIS_PROVE [] ``b /\ (b1 ==> b2) ==> ((b ==> b1) ==> b2)``

val TYPE_SUBST_EMPTY = prove(
  ``(!ty. TYPE_SUBST [] ty = ty)``,
  HO_MATCH_MP_TAC type_INDUCT_ALT
  \\ FULL_SIMP_TAC std_ss [TYPE_SUBST,REV_ASSOCD,EVERY_DEF]
  \\ REPEAT STRIP_TAC \\ AP_TERM_TAC
  \\ Induct_on `xs` \\ FULL_SIMP_TAC std_ss [MAP,EVERY_DEF]);

val INST_ALT_EMPTY = prove(
  ``!tm env.
      EVERY (\(x,y). x = y) env ==>
      (INST_ALT env [] tm = Result tm)``,
  completeInduct_on `sizeof tm` \\ HO_MATCH_MP_TAC term_CASES
  \\ REPEAT CONJ_TAC \\ REPEAT STRIP_TAC
  THEN1 (ONCE_REWRITE_TAC [INST_ALT] \\ SIMP_TAC std_ss [TYPE_SUBST_EMPTY]
    \\ `REV_ASSOCD (Var a0 a1) env (Var a0 a1) = Var a0 a1` by ALL_TAC THEN1
     (POP_ASSUM MP_TAC \\ REPEAT (POP_ASSUM (K ALL_TAC))
      \\ Induct_on `env` \\ FULL_SIMP_TAC std_ss [REV_ASSOCD]
      \\ Cases \\ FULL_SIMP_TAC std_ss [REV_ASSOCD,EVERY_DEF])
    \\ FULL_SIMP_TAC std_ss [])
  THEN1 (ONCE_REWRITE_TAC [INST_ALT] \\ SIMP_TAC std_ss [TYPE_SUBST_EMPTY])
  THEN1 (ONCE_REWRITE_TAC [INST_ALT] \\ SIMP_TAC std_ss [TYPE_SUBST_EMPTY])
  THEN1 (ONCE_REWRITE_TAC [INST_ALT] \\ SIMP_TAC std_ss [TYPE_SUBST_EMPTY])
  THEN1
   (FULL_SIMP_TAC std_ss [sizeof,term_ok]
    \\ FULL_SIMP_TAC std_ss [PULL_FORALL]
    \\ ONCE_REWRITE_TAC [INST_ALT]
    \\ FIRST_X_ASSUM (fn th => MP_TAC (Q.SPECL [`a0:term`,`env`] th) THEN
                               MP_TAC (Q.SPECL [`a1:term`,`env`] th))
    \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1 DECIDE_TAC
    \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
    \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1 DECIDE_TAC
    \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
    \\ FULL_SIMP_TAC std_ss [IS_CLASH,RESULT])
  \\ ONCE_REWRITE_TAC [INST_ALT]
  \\ FULL_SIMP_TAC std_ss [TYPE_SUBST_EMPTY,PULL_FORALL,sizeof]
  \\ FIRST_X_ASSUM (MP_TAC o Q.SPECL [`a2`,`((Var a0 a1,Var a0 a1)::env)`])
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1 DECIDE_TAC
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF,IS_RESULT,RESULT])
  |> Q.SPECL [`tm`,`[]`] |> SIMP_RULE std_ss [EVERY_DEF] |> GEN_ALL;

val TYPE_SUBST_TWICE = prove(
  ``!ty2. TYPE_SUBST (MAP (\(x,y). (TYPE_SUBST Y x,y)) X ++ Y) ty2 =
          TYPE_SUBST Y (TYPE_SUBST X ty2)``,
  HO_MATCH_MP_TAC type_INDUCT_ALT \\ FULL_SIMP_TAC std_ss [TYPE_SUBST]
  \\ REPEAT STRIP_TAC
  THEN1 (AP_TERM_TAC \\ Induct_on `xs` \\ FULL_SIMP_TAC std_ss [MAP,EVERY_DEF])
  \\ Induct_on `X`
  THEN1 (FULL_SIMP_TAC std_ss [MAP,APPEND,REV_ASSOCD,TYPE_SUBST_EMPTY,TYPE_SUBST])
  \\ Cases \\ FULL_SIMP_TAC std_ss [MAP,APPEND,REV_ASSOCD]
  \\ Cases_on `r = Tyvar v` \\ FULL_SIMP_TAC std_ss []);

val INST_ALT_term_ok = prove(
  ``!tm tyin env.
      (!s1 s2. MEM (s1,s2) tyin ==> type_ok defs s1) /\ term_ok defs tm ==>
      (!res. (INST_ALT env tyin tm = Result res) ==> term_ok defs res) /\
      (!var. (INST_ALT env tyin tm = Clash var) ==> term_ok defs var)``,
  completeInduct_on `sizeof tm` \\ HO_MATCH_MP_TAC term_CASES
  \\ REPEAT CONJ_TAC \\ NTAC 5 STRIP_TAC
  THEN1 (ONCE_REWRITE_TAC [INST_ALT]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ METIS_TAC [type_ok_TYPE_SUBST])
  THEN1 (ONCE_REWRITE_TAC [INST_ALT]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    THEN1 (METIS_TAC [type_ok_TYPE_SUBST])
    \\ Q.LIST_EXISTS_TAC [`ty2`] \\ FULL_SIMP_TAC std_ss [GSYM TYPE_SUBST_TWICE]
    \\ METIS_TAC [])
  THEN1 (ONCE_REWRITE_TAC [INST_ALT]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ METIS_TAC [type_ok_TYPE_SUBST,term_ok])
  THEN1 (ONCE_REWRITE_TAC [INST_ALT]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ SRW_TAC [] [result_DISTINCT,result_INJ,term_ok]
    \\ METIS_TAC [type_ok_TYPE_SUBST,term_ok])
  THEN1
   (FULL_SIMP_TAC std_ss [sizeof,term_ok] \\ STRIP_TAC
    \\ FULL_SIMP_TAC std_ss [PULL_FORALL]
    \\ ONCE_REWRITE_TAC [INST_ALT]
    \\ Cases_on `IS_CLASH (INST_ALT env tyin a0)`
    \\ ASM_SIMP_TAC std_ss [] THEN1
     (FULL_SIMP_TAC std_ss [AND_IMP_INTRO] \\ NTAC 2 STRIP_TAC
      \\ FIRST_X_ASSUM MATCH_MP_TAC \\ FULL_SIMP_TAC std_ss []
      \\ REPEAT STRIP_TAC THEN1 DECIDE_TAC \\ RES_TAC)
    \\ Cases_on `IS_CLASH (INST_ALT env tyin a1)`
    \\ ASM_SIMP_TAC std_ss [] THEN1
     (FULL_SIMP_TAC std_ss [AND_IMP_INTRO] \\ NTAC 2 STRIP_TAC
      \\ FIRST_X_ASSUM MATCH_MP_TAC \\ FULL_SIMP_TAC std_ss []
      \\ REPEAT STRIP_TAC THEN1 DECIDE_TAC \\ RES_TAC)
    \\ SIMP_TAC std_ss [result_INJ,result_DISTINCT,term_ok]
    \\ STRIP_TAC THENL
     [FIRST_X_ASSUM (MP_TAC o Q.SPEC `a0:term`),
      FIRST_X_ASSUM (MP_TAC o Q.SPEC `a1:term`)]
    \\ FULL_SIMP_TAC std_ss [GSYM PULL_FORALL]
    \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC
    \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
    \\ IMP_RES_TAC NOT_IS_CLASH_IMP_Result \\ RES_TAC
    \\ FULL_SIMP_TAC std_ss [RESULT]
    \\ DECIDE_TAC)
  \\ ONCE_REWRITE_TAC [INST_ALT] \\ STRIP_TAC
  \\ Q.ABBREV_TAC `env1 = ((Var a0 a1,Var a0 (TYPE_SUBST tyin a1))::env)`
  \\ Cases_on `IS_RESULT (INST_ALT env1 tyin a2)`
  \\ ASM_SIMP_TAC std_ss [result_INJ,result_DISTINCT,term_ok] THEN1
   (REPEAT STRIP_TAC THEN1 METIS_TAC [type_ok_TYPE_SUBST]
    \\ IMP_RES_TAC IS_RESULT_IMP_Result \\ FULL_SIMP_TAC std_ss [RESULT]
    \\ FULL_SIMP_TAC std_ss [PULL_FORALL]
    \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `a2:term`)
    \\ FULL_SIMP_TAC std_ss [GSYM PULL_FORALL,sizeof]
    \\ REPEAT STRIP_TAC \\ RES_TAC)
  \\ IMP_RES_TAC NOT_IS_RESULT_IMP_Clash \\ FULL_SIMP_TAC std_ss [CLASH]
  \\ Cases_on `Var a0 (TYPE_SUBST tyin a1) <> var`
  \\ ASM_SIMP_TAC std_ss [result_INJ,result_DISTINCT,term_ok] THEN1
   (FULL_SIMP_TAC std_ss [PULL_FORALL]
    \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `a2:term`)
    \\ FULL_SIMP_TAC std_ss [GSYM PULL_FORALL,sizeof]
    \\ REPEAT STRIP_TAC \\ RES_TAC)
  \\ FULL_SIMP_TAC std_ss []
  \\ Q.ABBREV_TAC `vv = VARIANT (RESULT (INST_ALT [] tyin a2))`
  \\ Q.ABBREV_TAC `env2 = ((Var (vv a0 (TYPE_SUBST tyin a1)) a1,
             Var (vv a0 (TYPE_SUBST tyin a1)) (TYPE_SUBST tyin a1)) :: env)`
  \\ Cases_on `IS_RESULT (INST_ALT env2 tyin
           (VSUBST [(Var (vv a0 (TYPE_SUBST tyin a1)) a1,Var a0 a1)] a2))`
  \\ ASM_SIMP_TAC std_ss [result_INJ,result_DISTINCT,term_ok]
  \\ IMP_RES_TAC NOT_IS_RESULT_IMP_Clash \\ FULL_SIMP_TAC std_ss [CLASH]
  \\ IMP_RES_TAC IS_RESULT_IMP_Result \\ FULL_SIMP_TAC std_ss [RESULT]
  \\ FULL_SIMP_TAC std_ss [PULL_FORALL]
  \\ ASM_SIMP_TAC std_ss [result_INJ,result_DISTINCT,term_ok]
  \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC
       `(VSUBST [(Var (vv a0 (TYPE_SUBST tyin a1)) a1,Var a0 a1)] a2):term`)
  \\ FULL_SIMP_TAC std_ss [GSYM PULL_FORALL,sizeof,
       SIZEOF_VSUBST |> Q.SPECL [`tm`,`[Var v ty, Var v' ty']`]
         |> SIMP_RULE std_ss [MEM,term_INJ]]
  \\ METIS_TAC [term_ok_VSUBST |> Q.SPECL [`tm`,`[Var v ty, Var v' ty']`]
           |> SIMP_RULE std_ss [MEM,term_INJ,EVERY_DEF,term_ok],type_ok_TYPE_SUBST]);

val INST_CORE_LEMMA =
  INST_CORE_HAS_TYPE |> Q.SPECL [`tm`,`[]`,`tyin`]
  |> SIMP_RULE std_ss [MEM,REV_ASSOCD] |> Q.GENL [`tm`,`tyin`]

val term_ok_IMP_type_ok = prove(
  ``!x. welltyped x /\ term_ok defs x ==> type_ok defs (typeof x)``,
  HO_MATCH_MP_TAC term_INDUCT
  \\ FULL_SIMP_TAC std_ss [term_ok,typeof,type_ok_Fun,type_ok_Bool,WELLTYPED_CLAUSES]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [codomain,type_ok_Fun]);


val LENGTH_EQ_FILTER_FILTER = prove(
  ``!xs. EVERY (\x. (P x \/ Q x) /\ ~(P x /\ Q x)) xs ==>
         (LENGTH xs = LENGTH (FILTER P xs) + LENGTH (FILTER Q xs))``,
  Induct \\ SIMP_TAC std_ss [LENGTH,FILTER,EVERY_DEF] \\ STRIP_TAC
  \\ Cases_on `P h` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD_CLAUSES]);

val string_lt = prove(
  ``!x y. string_lt x y = x < y``,
  Induct \\ Cases_on `y`
  \\ FULL_SIMP_TAC std_ss [string_lt,stringTheory.string_lt_def]
  \\ REPEAT STRIP_TAC \\ SRW_TAC [] [stringTheory.char_lt_def]);

val LENGTH_INORDER_INSERT = prove(
  ``!xs. ALL_DISTINCT (x::xs) ==> (LENGTH (INORDER_INSERT x xs) = SUC (LENGTH xs))``,
  FULL_SIMP_TAC std_ss [INORDER_INSERT,LENGTH_APPEND,LENGTH]
  \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT] \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [DECIDE ``1 + n = SUC n``]
  \\ FULL_SIMP_TAC std_ss [GSYM ADD1,ADD_CLAUSES]
  \\ MATCH_MP_TAC (GSYM LENGTH_EQ_FILTER_FILTER)
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM] \\ REPEAT STRIP_TAC
  \\ Q.MATCH_ASSUM_RENAME_TAC `MEM y xs` []
  \\ FULL_SIMP_TAC std_ss [string_lt]
  \\ Cases_on `x = y` \\ FULL_SIMP_TAC std_ss []
  \\ METIS_TAC [stringTheory.string_lt_cases,stringTheory.string_lt_antisym]);

val ALL_DISTINCT_FILTER = prove(
  ``!xs P. ALL_DISTINCT xs ==> ALL_DISTINCT (FILTER P xs)``,
  Induct \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT,FILTER] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] [MEM_FILTER]);

val ALL_DISTINCT_INORDER_INSERT = prove(
  ``!xs h. ALL_DISTINCT xs ==> ALL_DISTINCT (INORDER_INSERT h xs)``,
  FULL_SIMP_TAC (srw_ss()) [ALL_DISTINCT,INORDER_INSERT,
    ALL_DISTINCT_APPEND,MEM_FILTER] \\ REPEAT STRIP_TAC
  \\ TRY (MATCH_MP_TAC ALL_DISTINCT_FILTER)
  \\ FULL_SIMP_TAC (srw_ss()) [string_lt,stringTheory.string_lt_nonrefl]
  \\ METIS_TAC [stringTheory.string_lt_antisym]);

val ALL_DISTINCT_ITLIST_INORDER_INSERT = prove(
  ``!xs. ALL_DISTINCT (ITLIST INORDER_INSERT xs [])``,
  Induct \\ SIMP_TAC std_ss [ITLIST,ALL_DISTINCT] \\ REPEAT STRIP_TAC
  \\ MATCH_MP_TAC ALL_DISTINCT_INORDER_INSERT \\ FULL_SIMP_TAC std_ss []);

val MEM_ITLIST_INORDER_INSERT = prove(
  ``!xs x. MEM x (ITLIST INORDER_INSERT xs []) = MEM x xs``,
  Induct \\ FULL_SIMP_TAC std_ss [ITLIST,INORDER_INSERT,MEM,MEM_APPEND,
    MEM_FILTER,string_lt] \\ METIS_TAC [stringTheory.string_lt_cases]);

val LENGTH_STRING_SORT = prove(
  ``!xs. ALL_DISTINCT xs ==> (LENGTH (STRING_SORT xs) = LENGTH xs)``,
  Induct \\ FULL_SIMP_TAC std_ss [STRING_SORT,ITLIST,LENGTH_INORDER_INSERT,LENGTH]
  \\ REPEAT STRIP_TAC  \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT]
  \\ IMP_RES_TAC LENGTH_INORDER_INSERT
  \\ `ALL_DISTINCT (h::ITLIST INORDER_INSERT xs [])` by ALL_TAC
  THEN1 (FULL_SIMP_TAC std_ss [ALL_DISTINCT,ALL_DISTINCT_ITLIST_INORDER_INSERT,
           MEM_ITLIST_INORDER_INSERT])
  \\ IMP_RES_TAC LENGTH_INORDER_INSERT
  \\ FULL_SIMP_TAC std_ss []);

val ALL_DISTINCT_STRING_UNION = prove(
  ``!xs ys. ALL_DISTINCT xs /\ ALL_DISTINCT ys ==>
            ALL_DISTINCT (STRING_UNION xs ys)``,
  Induct \\ FULL_SIMP_TAC std_ss [STRING_UNION,ITLIST]
  \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [STRING_INSERT] \\ SRW_TAC [] []);

val ALL_DISTINCT_tyvars = prove(
  ``!ty. ALL_DISTINCT (tyvars ty)``,
  HO_MATCH_MP_TAC type_INDUCT_ALT
  \\ FULL_SIMP_TAC (srw_ss()) [tyvars,ALL_DISTINCT,ALL_DISTINCT_STRING_UNION]
  \\ Induct \\ FULL_SIMP_TAC std_ss [ITLIST,ALL_DISTINCT]
  \\ REPEAT STRIP_TAC \\ MATCH_MP_TAC ALL_DISTINCT_STRING_UNION
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF]);

val ALL_DISTINCT_tvars = prove(
  ``!tm. ALL_DISTINCT (tvars tm)``,
  HO_MATCH_MP_TAC term_INDUCT
  \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT_tyvars,tvars,ALL_DISTINCT_STRING_UNION]);

val EVERY_TERM_UNION = prove(
  ``!x y P. EVERY P x /\ EVERY P y ==> EVERY P (TERM_UNION x y)``,
  Induct \\ FULL_SIMP_TAC std_ss [TERM_UNION] \\ SRW_TAC [] []);

val RACONV_IMP = prove(
  ``!x y env. RACONV env (x,y) /\ EVERY (\(t1,t2). typeof t1 = typeof t2) env ==>
              (typeof x = typeof y)``,
  HO_MATCH_MP_TAC term_INDUCT \\ REPEAT STRIP_TAC
  \\ REPEAT (POP_ASSUM MP_TAC) \\ Q.SPEC_TAC (`y`,`y`)
  \\ HO_MATCH_MP_TAC term_INDUCT \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [RACONV,typeof] THEN1
   (Induct_on `env` \\ FULL_SIMP_TAC std_ss [ALPHAVARS,term_INJ]
    \\ Cases \\ FULL_SIMP_TAC std_ss [EVERY_DEF]
    \\ REPEAT STRIP_TAC \\ METIS_TAC [typeof])
  THEN1 (METIS_TAC [])
  \\ FULL_SIMP_TAC std_ss [type_INJ]
  \\ Q.PAT_ASSUM `!x.bb` MATCH_MP_TAC
  \\ Q.EXISTS_TAC `((Var a0 a1,Var a0' a1')::env)`
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF,typeof]);

val ACONV_IMP = prove(
  ``!x y. ACONV x y ==> (typeof x = typeof y)``,
  SIMP_TAC std_ss [ACONV] \\ STRIP_TAC \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC RACONV_IMP \\ FULL_SIMP_TAC std_ss [EVERY_DEF]);

val myss = rewrites [welltyped_in,WELLTYPED_CLAUSES,typeof,type_INJ,
                     codomain,domain,term_ok,term_ok_IMP_type_ok,type_ok_Fun]

val THM_LEMMA = prove(
  ``!lhs rhs. (lhs |- rhs) ==>
              EVERY (\c. welltyped_in c (FST lhs)) (SND lhs) /\
              welltyped_in rhs (FST lhs) /\ (typeof rhs = Bool) /\
              EVERY (\c. typeof c = Bool) (SND lhs)``,
  HO_MATCH_MP_TAC proves_INDUCT \\ REPEAT CONJ_TAC
  \\ FULL_SIMP_TAC std_ss [TERM_def,equation,EVERY_DEF]
  THEN1 (FULL_SIMP_TAC (std_ss++myss) [])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ IMP_RES_TAC ACONV_IMP \\ FULL_SIMP_TAC (srw_ss()) [])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ IMP_RES_TAC ACONV_IMP \\ FULL_SIMP_TAC (srw_ss()) [] \\ METIS_TAC [])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ IMP_RES_TAC ACONV_IMP \\ FULL_SIMP_TAC (srw_ss()) [])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ IMP_RES_TAC ACONV_IMP \\ FULL_SIMP_TAC (srw_ss()) [])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ IMP_RES_TAC ACONV_IMP \\ FULL_SIMP_TAC (srw_ss()) []
         \\ FULL_SIMP_TAC std_ss [WELLTYPED]
         \\ IMP_RES_TAC has_type_INJ)
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ IMP_RES_TAC ACONV_IMP \\ FULL_SIMP_TAC (srw_ss()) []
         \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_FILTER])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ Q.PAT_ASSUM `context_ok defs` ASSUME_TAC
         \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_FILTER,type_ok_Bool])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) []
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC EVERY_TERM_UNION)
         \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_MAP,PULL_EXISTS,FORALL_PROD]
         \\ REPEAT STRIP_TAC \\ RES_TAC
         \\ SIMP_TAC std_ss [INST_DEF]
         \\ MP_TAC (INST_CORE_LEMMA |> Q.SPECL [`tyin`,`y`])
         \\ MP_TAC (INST_CORE_LEMMA |> Q.SPECL [`tyin`,`rhs`])
         \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
         \\ FULL_SIMP_TAC (srw_ss()) [RESULT,welltyped]
         \\ IMP_RES_TAC WELLTYPED_LEMMA
         \\ ASM_SIMP_TAC std_ss [TYPE_SUBST]
         \\ METIS_TAC [INST_ALT_term_ok])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) [] \\ REPEAT STRIP_TAC
         \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_MAP,PULL_EXISTS]
         \\ REPEAT STRIP_TAC \\ RES_TAC
         \\ TRY (MATCH_MP_TAC VSUBST_WELLTYPED)
         \\ TRY (MATCH_MP_TAC term_ok_VSUBST)
         \\ TRY (MATCH_MP_TAC typeof_VSUBST)
         \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_MAP,PULL_EXISTS,FORALL_PROD]
         \\ REPEAT STRIP_TAC \\ RES_TAC \\ METIS_TAC [])
  THEN1 (FULL_SIMP_TAC (std_ss++myss) [context_ok,term_ok_CONS,EVERY_MEM])
  THEN1 (Induct_on `defs` \\ FULL_SIMP_TAC std_ss [MEM,context_ok]
         \\ REVERSE (REPEAT STRIP_TAC)
         THEN1 (RES_TAC \\ FULL_SIMP_TAC std_ss [welltyped_in_CONS])
         THEN1 (RES_TAC \\ FULL_SIMP_TAC std_ss [welltyped_in_CONS])
         \\ POP_ASSUM (ASSUME_TAC o GSYM) \\ FULL_SIMP_TAC std_ss [def_ok]
         \\ FULL_SIMP_TAC (std_ss++myss) [context_ok,def_ok]
         \\ FULL_SIMP_TAC std_ss [WELLTYPED]
         \\ IMP_RES_TAC has_type_INJ
         \\ TRY (MATCH_MP_TAC term_ok_CONS)
         \\ FULL_SIMP_TAC (std_ss++myss) [])
  THEN1 (Induct_on `defs` \\ FULL_SIMP_TAC std_ss [MEM,context_ok]
         \\ REVERSE (REPEAT STRIP_TAC)
         THEN1 (RES_TAC \\ FULL_SIMP_TAC std_ss [welltyped_in_CONS])
         THEN1 (RES_TAC \\ FULL_SIMP_TAC std_ss [welltyped_in_CONS])
         \\ POP_ASSUM (ASSUME_TAC o GSYM) \\ FULL_SIMP_TAC std_ss [def_ok]
         \\ FULL_SIMP_TAC (std_ss++myss) [context_ok,def_ok]
         \\ REPEAT STRIP_TAC
         \\ TRY (MATCH_MP_TAC type_ok_CONS)
         \\ TRY (MATCH_MP_TAC term_ok_CONS)
         \\ FULL_SIMP_TAC (std_ss++myss) []
         \\ FULL_SIMP_TAC std_ss [WELLTYPED]
         \\ IMP_RES_TAC has_type_INJ
         \\ SIMP_TAC std_ss [consts,consts_aux,MAP,FLAT,APPEND,MEM]
         \\ Q.LIST_EXISTS_TAC [`typeof t`,`[]`]
         \\ FULL_SIMP_TAC std_ss [TYPE_SUBST_EMPTY])
  THEN  (Induct_on `defs` \\ FULL_SIMP_TAC std_ss [MEM,context_ok]
         \\ REVERSE (REPEAT STRIP_TAC)
         THEN1 (RES_TAC \\ FULL_SIMP_TAC std_ss [welltyped_in_CONS])
         THEN1 (RES_TAC \\ FULL_SIMP_TAC std_ss [welltyped_in_CONS])
         \\ Q.PAT_ASSUM `!x y. bbb` (K ALL_TAC)
         \\ POP_ASSUM (ASSUME_TAC o GSYM) \\ FULL_SIMP_TAC std_ss [def_ok]
         \\ FULL_SIMP_TAC (std_ss++myss) [context_ok,def_ok]
         \\ FULL_SIMP_TAC std_ss [typeof,codomain,welltyped_in_Comb,GSYM CONJ_ASSOC]
         \\ `type_ok (Typedef tyname t a r::defs)
               (Tyapp tyname (MAP Tyvar (STRING_SORT (tvars t))))` by ALL_TAC THEN1
          (ONCE_REWRITE_TAC [type_ok_CASES]
           \\ SIMP_TAC (srw_ss()) [type_DISTINCT,type_INJ,MEM_MAP,PULL_EXISTS]
           \\ FULL_SIMP_TAC std_ss [types,types_aux,FLAT,APPEND,MAP,MEM]
           \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT_tvars,LENGTH_STRING_SORT]
           \\ REPEAT STRIP_TAC
           \\ ONCE_REWRITE_TAC [type_ok_CASES]
           \\ SIMP_TAC (srw_ss()) [type_DISTINCT,type_INJ,MEM_MAP,PULL_EXISTS])
         \\ FULL_SIMP_TAC std_ss [type_ok_Bool]
         \\ IMP_RES_TAC term_ok_IMP_type_ok
         \\ POP_ASSUM MP_TAC \\ FULL_SIMP_TAC std_ss [type_ok_Fun]
         \\ REPEAT STRIP_TAC \\ TRY (MATCH_MP_TAC type_ok_CONS)
         \\ TRY (MATCH_MP_TAC term_ok_CONS)
         \\ FULL_SIMP_TAC (std_ss++myss) []
         \\ ONCE_REWRITE_TAC [type_ok_CASES]
         \\ SIMP_TAC std_ss [type_DISTINCT,type_INJ]
         \\ SIMP_TAC std_ss [consts,consts_aux,MAP,FLAT,APPEND,MEM]
         \\ FULL_SIMP_TAC std_ss [type_ok_Fun,domain]
         \\ FULL_SIMP_TAC std_ss []
         \\ METIS_TAC [TYPE_SUBST_EMPTY]));

val THM = prove(
  ``THM defs (Sequent asl c) ==> EVERY (TERM defs) asl /\ TERM defs c``,
  SIMP_TAC std_ss [THM_def] \\ REPEAT STRIP_TAC \\ IMP_RES_TAC THM_LEMMA
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM,TERM_def,MEM_MAP,PULL_EXISTS]);

(* ------------------------------------------------------------------------- *)
(* Verification of type functions                                            *)
(* ------------------------------------------------------------------------- *)

val can_thm = prove(
  ``can f x s = case f x s of (HolRes _,s) => (HolRes T,s) |
                              (_,s) => (HolRes F,s)``,
  SIMP_TAC std_ss [can_def,ex_bind_def,otherwise_def]
  \\ Cases_on `f x s` \\ Cases_on `q`
  \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]);

val assoc_thm = prove(
  ``!xs y z s s'.
      (assoc y xs s = (z, s')) ==>
      (s' = s) /\ (!i. (z = HolRes i) ==> MEM (y,i) xs) /\
                  (!e. (z = HolErr e) ==> !i. ~MEM (y,i) xs)``,
  Induct \\ SIMP_TAC (srw_ss()) [Once assoc_def,failwith_def]
  \\ Cases \\ SIMP_TAC (srw_ss()) [] \\ STRIP_TAC
  \\ Cases_on `y = q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ METIS_TAC []);

val get_type_arity_thm = prove(
  ``!name s z s'.
      (get_type_arity name s = (z,s')) ==> (s' = s) /\
      (!i. (z = HolRes i) ==> MEM (name,i) s.the_type_constants) /\
      (!e. (z = HolErr e) ==> !i. ~MEM (name,i) s.the_type_constants)``,
  SIMP_TAC (srw_ss()) [get_type_arity_def,ex_bind_def,
    get_the_type_constants_def] \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC assoc_thm);

val mk_vartype_thm = store_thm("mk_vartype_thm",
  ``!name s.
      TYPE s.the_definitions (mk_vartype name)``,
  SIMP_TAC (srw_ss()) [mk_vartype_def,TYPE_def,hol_ty_def,
    Once type_ok_CASES,type_INJ]);

val ALL_DISTINCT_LEMMA = prove(
  ``ALL_DISTINCT (xs ++ ys) ==> EVERY (\y. ~MEM y xs) ys``,
  SIMP_TAC std_ss [ALL_DISTINCT_APPEND,EVERY_MEM] \\ METIS_TAC []);

val mk_type_thm = store_thm("mk_type_thm",
  ``!tyop args s z s'.
      STATE s defs /\ EVERY (TYPE defs) args /\
      (mk_type (tyop,args) s = (z,s')) ==> (s' = s) /\
      ((tyop = "fun") /\ (LENGTH args = 2) ==> ?i. z = HolRes i) /\
      !i. (z = HolRes i) ==> TYPE defs i /\ (i = Tyapp tyop args)``,
  SIMP_TAC std_ss [mk_type_def,try_def,ex_bind_def,otherwise_def]
  \\ NTAC 3 STRIP_TAC \\ Cases_on `get_type_arity tyop s`
  \\ IMP_RES_TAC get_type_arity_thm
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def,ex_return_def]
  \\ SRW_TAC [] [ex_return_def]
  \\ FULL_SIMP_TAC std_ss [TYPE_def,hol_ty_def]
  \\ SRW_TAC [] [] \\ SIMP_TAC std_ss [Once type_ok_CASES,type_INJ]
  THEN1 (Cases_on `args` \\ FULL_SIMP_TAC std_ss [LENGTH]
         \\ Cases_on `t` \\ FULL_SIMP_TAC std_ss [LENGTH]
         \\ Cases_on `t'` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1,LENGTH_NIL,
              EVERY_DEF,HD,EVAL ``EL 1 (x::y::xs)``,TYPE_def])
  \\ SIMP_TAC std_ss [LENGTH_MAP,MEM_MAP,PULL_EXISTS]
  \\ NTAC 3 (POP_ASSUM MP_TAC) \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [STATE_def,MEM_APPEND,MEM,LENGTH_NIL,LET_DEF]
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM,TYPE_def]
  \\ REPEAT STRIP_TAC \\ NTAC 4 (POP_ASSUM MP_TAC)
  \\ FULL_SIMP_TAC std_ss [MEM_APPEND,MEM,MAP,MAP_APPEND]
  \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC ALL_DISTINCT_LEMMA
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF]
  \\ FULL_SIMP_TAC (srw_ss()) [MEM_MAP,FORALL_PROD]
  \\ CCONTR_TAC \\ FULL_SIMP_TAC std_ss []
  \\ Q.PAT_ASSUM `r.the_type_constants = xxx` ASSUME_TAC
  \\ FULL_SIMP_TAC std_ss [MAP,MAP_APPEND,ALL_DISTINCT_APPEND,MEM,
       FORALL_PROD,MEM_MAP,PULL_EXISTS] \\ RES_TAC
  \\ Q.PAT_ASSUM `defs = r.the_definitions` ASSUME_TAC
  \\ FULL_SIMP_TAC std_ss [] \\ RES_TAC \\ FULL_SIMP_TAC std_ss []);

val dest_type_thm = store_thm("dest_type_thm",
  ``!ty s z s'.
      STATE s defs /\
      (dest_type ty s = (z,s')) /\ TYPE defs ty ==> (s' = s) /\
      !i. (z = HolRes i) ==> ?n tys. (ty = Tyapp n tys) /\ (i = (n,tys)) /\
                                     EVERY (TYPE defs) tys``,
  Cases \\ FULL_SIMP_TAC (srw_ss()) [dest_type_def,failwith_def,ex_return_def]
  \\ FULL_SIMP_TAC std_ss [TYPE_def,hol_ty_def] \\ SRW_TAC [] [] THEN1
   (Cases_on `l` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1]
    \\ Cases_on `t` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1]
    \\ Cases_on `t'` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1]
    \\ FULL_SIMP_TAC std_ss [HD, EVAL ``EL 1 (x::y::xs)``,EVERY_DEF]
    \\ NTAC 2 (POP_ASSUM MP_TAC)
    \\ FULL_SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_INJ,TYPE_def,type_DISTINCT]
    \\ REPEAT STRIP_TAC \\ `F` by DECIDE_TAC)
  \\ Cases_on `l` \\ SIMP_TAC std_ss [EVERY_DEF]
  \\ POP_ASSUM MP_TAC
  \\ SIMP_TAC std_ss [Once type_ok_CASES]
  \\ SIMP_TAC std_ss [type_INJ,TYPE_def,type_DISTINCT,EVERY_MEM,MEM_MAP,
      PULL_EXISTS,LENGTH_MAP,MEM]);

val dest_vartype_thm = store_thm("dest_vartype_thm",
  ``!ty s z s'.
      (dest_vartype ty s = (z,s')) ==> (s' = s) /\
      !i. (z = HolRes i) ==> (ty = Tyvar i)``,
  Cases \\ FULL_SIMP_TAC (srw_ss())
    [dest_vartype_def,failwith_def,ex_return_def]);

val is_type_thm = store_thm("is_type_thm",
  ``!ty. is_type ty = ?s tys. ty = Tyapp s tys``,
  Cases \\ SIMP_TAC (srw_ss()) [is_type_def]);

val is_vartype_thm = store_thm("is_vartype_thm",
  ``!ty. is_vartype ty = ?s. ty = Tyvar s``,
  Cases \\ SIMP_TAC (srw_ss()) [is_vartype_def]);

val MEM_union = prove(
  ``!xs ys x. MEM x (union xs ys) = MEM x xs \/ MEM x ys``,
  Induct \\ FULL_SIMP_TAC std_ss [union_def]
  \\ ONCE_REWRITE_TAC [itlist_def] \\ SRW_TAC [] [insert_def]
  \\ METIS_TAC []);

val MEM_STRING_UNION = prove(
  ``!xs ys x. MEM x (STRING_UNION xs ys) = MEM x xs \/ MEM x ys``,
  Induct \\ FULL_SIMP_TAC std_ss [STRING_UNION]
  \\ ONCE_REWRITE_TAC [ITLIST] \\ SRW_TAC [] [STRING_INSERT]
  \\ METIS_TAC []);

val ITLIST_MAP = prove(
  ``!xs b. ITLIST f (MAP g xs) b = ITLIST (f o g) xs b``,
  Induct \\ FULL_SIMP_TAC std_ss [MAP,ITLIST]);

val tyvars_thm = prove(
  ``!ty s. MEM s (tyvars ty) = MEM s (tyvars (hol_ty ty))``,
  HO_MATCH_MP_TAC tyvars_ind \\ REPEAT STRIP_TAC
  \\ Cases_on `ty` \\ FULL_SIMP_TAC (srw_ss()) [type_INJ,type_DISTINCT]
  \\ SIMP_TAC (srw_ss()) [Once hol_kernelTheory.tyvars_def,Once tyvars,hol_ty_def]
  \\ SRW_TAC [] [tyvars]
  THEN1 (FULL_SIMP_TAC (srw_ss()) [tyvars,Once itlist_def])
  THEN1 (FULL_SIMP_TAC (srw_ss()) [tyvars,Once itlist_def])
  THEN1
   (FULL_SIMP_TAC (srw_ss()) [tyvars,Once itlist_def]
    \\ Cases_on `l` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1]
    \\ Cases_on `t` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1]
    \\ Cases_on `t'` \\ FULL_SIMP_TAC std_ss [LENGTH,ADD1]
    \\ FULL_SIMP_TAC std_ss [HD, EVAL ``EL 1 (x::y::xs)``,EVERY_DEF]
    \\ FULL_SIMP_TAC (srw_ss()) [MEM,MAP,Once itlist_def]
    \\ FULL_SIMP_TAC (srw_ss()) [MEM,MAP,Once itlist_def]
    \\ FULL_SIMP_TAC std_ss [MEM_union,MEM,MEM_STRING_UNION]
    \\ `F` by DECIDE_TAC)
  \\ SIMP_TAC (srw_ss()) [Once tyvars] \\ NTAC 3 (POP_ASSUM (K ALL_TAC))
  \\ FULL_SIMP_TAC std_ss [ITLIST_MAP]
  \\ Induct_on `l`
  \\ SIMP_TAC (srw_ss()) [Once itlist_def,ITLIST,MEM_union,MEM_STRING_UNION]
  \\ METIS_TAC []);

val lemma = prove(``(if x = y then f y else f x) = f x``,METIS_TAC[]);

val type_subst_thm = store_thm("type_subst",
  ``!i ty.
      (hol_ty (type_subst i ty) =
       TYPE_SUBST (MAP (\(n,t). (hol_ty n,hol_ty t)) i) (hol_ty ty)) /\
      (EVERY (\(x,y). TYPE s x /\ TYPE s y) i /\ TYPE s ty ==>
       TYPE s (type_subst i ty))``,
  HO_MATCH_MP_TAC type_subst_ind \\ STRIP_TAC \\ Cases THEN1
   (SIMP_TAC (srw_ss()) [Once type_subst_def]
    \\ SIMP_TAC (srw_ss()) [Once type_subst_def]
    \\ SIMP_TAC std_ss [hol_ty_def,TYPE_SUBST]
    \\ Induct_on `i` \\ TRY Cases \\ ONCE_REWRITE_TAC [rev_assocd_def]
    \\ SIMP_TAC (srw_ss()) [REV_ASSOCD,MAP]
    \\ Cases_on `r = Tyvar s'` \\ FULL_SIMP_TAC std_ss [hol_ty_def]
    \\ SRW_TAC [] []
    \\ Cases_on `r` \\ FULL_SIMP_TAC std_ss [hol_ty_def,type_INJ]
    \\ `F` by ALL_TAC \\ POP_ASSUM MP_TAC \\ SIMP_TAC std_ss []
    \\ SRW_TAC [] [type_DISTINCT])
  \\ SIMP_TAC (srw_ss()) [] \\ STRIP_TAC
  \\ ONCE_REWRITE_TAC [type_subst_def] \\ SIMP_TAC (srw_ss()) []
  \\ SIMP_TAC std_ss [LET_DEF,lemma]
  \\ Cases_on `l = []`
  THEN1 (FULL_SIMP_TAC std_ss [MAP,hol_ty_def] \\ SRW_TAC [] [TYPE_SUBST])
  \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `LENGTH l = 2` THEN1
   (FULL_SIMP_TAC (srw_ss()) [LENGTH_EQ_2]
    \\ SRW_TAC [] [] \\ FULL_SIMP_TAC std_ss [TYPE_SUBST,MAP]
    \\ FULL_SIMP_TAC (srw_ss()) [TYPE_def,hol_ty_def]
    \\ Cases_on `s' = "fun"` \\ FULL_SIMP_TAC std_ss [TYPE_SUBST,MAP]
    \\ FULL_SIMP_TAC (srw_ss()) [TYPE_def,hol_ty_def]
    \\ SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_DISTINCT,type_INJ]
    \\ NTAC 2 (POP_ASSUM MP_TAC)
    \\ SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_DISTINCT,type_INJ]
    \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC [])
  \\ FULL_SIMP_TAC std_ss [hol_ty_def,LENGTH_MAP,GSYM LENGTH_NIL]
  \\ FULL_SIMP_TAC std_ss [TYPE_SUBST,type_INJ]
  \\ STRIP_TAC THEN1
   (NTAC 2 (POP_ASSUM (K ALL_TAC)) \\ Induct_on `l`
    \\ FULL_SIMP_TAC (srw_ss()) [MAP,MEM])
  \\ FULL_SIMP_TAC std_ss [TYPE_def,hol_ty_def,LENGTH_MAP,GSYM LENGTH_NIL]
  \\ STRIP_TAC
  \\ SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_DISTINCT,type_INJ]
  \\ FULL_SIMP_TAC std_ss [MEM_MAP,PULL_EXISTS,EVERY_MEM,FORALL_PROD]
  \\ POP_ASSUM MP_TAC
  \\ SIMP_TAC (srw_ss()) [Once type_ok_CASES,type_DISTINCT,type_INJ]
  \\ FULL_SIMP_TAC std_ss [MEM_MAP,PULL_EXISTS,EVERY_MEM,FORALL_PROD]
  \\ METIS_TAC []);

val mk_fun_ty_thm = store_thm("mk_fun_ty_thm",
  ``!ty1 ty2 s z s'.
      STATE s defs /\ EVERY (TYPE defs) [ty1;ty2] /\
      (mk_fun_ty ty1 ty2 s = (z,s')) ==> (s' = s) /\
      ?i. (z = HolRes i) /\ (i = Tyapp "fun" [ty1;ty2]) /\ TYPE defs i``,
  SIMP_TAC std_ss [mk_fun_ty_def] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [BASIC_TYPE]
  \\ IMP_RES_TAC mk_type_thm \\ FULL_SIMP_TAC (srw_ss()) []);

(* ------------------------------------------------------------------------- *)
(* Verification of term functions                                            *)
(* ------------------------------------------------------------------------- *)

val get_const_type_thm = prove(
  ``!name s z s'.
      (get_const_type name s = (z,s')) ==> (s' = s) /\
      (!i. (z = HolRes i) ==> MEM (name,i) s.the_term_constants) /\
      (!e. (z = HolErr e) ==> !i. ~(MEM (name,i) s.the_term_constants))``,
  SIMP_TAC (srw_ss()) [get_const_type_def,ex_bind_def,
    get_the_term_constants_def] \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC assoc_thm);

val term_type_def = Define `
  term_type tm =
    case tm of
      Var _ ty => ty
    | Const _ ty => ty
    | Comb s _ => (case term_type s of Tyapp "fun" (_::ty1::_) => ty1
                                    | _ => Tyvar "")
    | Abs (Var _ ty) t => Tyapp "fun" [ty; term_type t]
    | _ => Tyvar ""`

val term_type = prove(
  ``!defs tm. TERM defs tm ==> (hol_ty (term_type tm) = typeof (hol_tm tm)) /\
                               TYPE defs (term_type tm)``,
  ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ STRIP_TAC \\ Induct \\ ONCE_REWRITE_TAC [term_type_def]
  \\ SIMP_TAC (srw_ss()) [hol_tm_def,typeof]
  \\ TRY (REPEAT STRIP_TAC \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss [])
  THEN1 (IMP_RES_TAC TERM \\ SRW_TAC [] [typeof,domain,hol_ty_def,codomain]
    \\ SRW_TAC [] [typeof,domain,hol_ty_def,codomain]
    \\ IMP_RES_TAC Select_type \\ IMP_RES_TAC Equal_type
    \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC [])
  THEN1
   (IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ Q.PAT_ASSUM `TERM defs (Comb s h)` MP_TAC
    \\ FULL_SIMP_TAC std_ss [TERM_def,hol_tm_def,welltyped_in,
         WELLTYPED_CLAUSES,term_ok] \\ REPEAT STRIP_TAC
    \\ FULL_SIMP_TAC std_ss [codomain]
    \\ Cases_on `term_type tm` \\ FULL_SIMP_TAC std_ss [hol_ty_def,type_DISTINCT]
    \\ NTAC 2 (POP_ASSUM MP_TAC)
    \\ SRW_TAC [] [type_DISTINCT]
    \\ IMP_RES_TAC LENGTH_EQ_2
    \\ FULL_SIMP_TAC (srw_ss()) [type_INJ])
  THEN1
   (IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ Q.PAT_ASSUM `TERM defs (Comb s h)` MP_TAC
    \\ FULL_SIMP_TAC std_ss [TERM_def,hol_tm_def,welltyped_in,
         WELLTYPED_CLAUSES,term_ok] \\ REPEAT STRIP_TAC
    \\ FULL_SIMP_TAC std_ss [codomain]
    \\ Cases_on `term_type tm` \\ FULL_SIMP_TAC std_ss [hol_ty_def,type_DISTINCT]
    \\ NTAC 2 (POP_ASSUM MP_TAC)
    \\ SRW_TAC [] [type_DISTINCT]
    \\ IMP_RES_TAC LENGTH_EQ_2
    \\ FULL_SIMP_TAC (srw_ss()) [type_INJ]
    \\ IMP_RES_TAC TYPE \\ FULL_SIMP_TAC std_ss [EVERY_DEF])
  \\ IMP_RES_TAC Abs_Var \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC TERM
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,typeof,hol_ty_def,BASIC_TYPE]);

val type_of_thm = prove(
  ``!tm. TERM defs tm /\ STATE s defs ==>
         (type_of tm s = (HolRes (term_type tm),s))``,
  HO_MATCH_MP_TAC type_of_ind \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `tm` \\ ONCE_REWRITE_TAC [type_of_def]
  \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def,hol_tm_def,typeof]
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
  \\ TRY (FULL_SIMP_TAC (srw_ss()) [Once term_type_def] \\ NO_TAC)
  THEN1
   (ONCE_REWRITE_TAC [ex_bind_def]
    \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC (srw_ss()) []
    \\ ONCE_REWRITE_TAC [ex_bind_def]
    \\ FULL_SIMP_TAC (srw_ss()) [dest_type_def]
    \\ `?ty1 ty2. term_type h = Tyapp "fun" [ty1;ty2]` by
     (`hol_ty (term_type h) = typeof (hol_tm h)` by ALL_TAC
      THEN1 IMP_RES_TAC term_type
      \\ POP_ASSUM (ASSUME_TAC o GSYM)
      \\ FULL_SIMP_TAC std_ss [TERM_def,hol_tm_def,welltyped_in,WELLTYPED_CLAUSES]
      \\ FULL_SIMP_TAC std_ss [term_ok]
      \\ Q.PAT_ASSUM `hol_ty (term_type h) = Fun (typeof (hol_tm t0)) rty` ASSUME_TAC
      \\ Cases_on `term_type h`
      \\ FULL_SIMP_TAC std_ss [hol_ty_def,type_DISTINCT]
      \\ NTAC 2 (POP_ASSUM MP_TAC)
      \\ SRW_TAC [] [type_DISTINCT]
      \\ IMP_RES_TAC LENGTH_EQ_2
      \\ FULL_SIMP_TAC (srw_ss()) [type_INJ])
    \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def,hol_ty_def,codomain]
    \\ IMP_RES_TAC TYPE \\ ASM_SIMP_TAC (srw_ss()) [EVERY_DEF,Once term_type_def])
  \\ IMP_RES_TAC Abs_Var
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,typeof,ex_bind_def]
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC (srw_ss()) [] \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ ASM_SIMP_TAC (srw_ss()) [Once term_type_def]
  \\ Cases_on `mk_fun_ty ty (term_type h0) s`
  \\ FULL_SIMP_TAC std_ss []
  \\ `EVERY (TYPE defs) [ty; term_type h0]` by ALL_TAC
  THEN1 FULL_SIMP_TAC std_ss [EVERY_DEF,term_type]
  \\ IMP_RES_TAC mk_fun_ty_thm
  \\ FULL_SIMP_TAC std_ss []);

val alphavars_thm = prove(
  ``!env.
      STATE s defs /\ TERM defs tm1 /\ TERM defs tm2 /\
      EVERY (\(v1,v2). TERM defs v1 /\ TERM defs v2) env ==>
      (alphavars env tm1 tm2 = ALPHAVARS
         (MAP (\(v1,v2). (hol_tm v1, hol_tm v2)) env) (hol_tm tm1, hol_tm tm2))``,
  Induct \\ SIMP_TAC (srw_ss()) [Once alphavars_def,ALPHAVARS]
  THEN1 METIS_TAC [TERM_11] \\ Cases \\ FULL_SIMP_TAC (srw_ss()) []
  \\ METIS_TAC [TERM_11]);

val TERM_Var = prove(
  ``STATE s defs /\ TYPE defs ty ==> TERM defs (Var n ty)``,
  FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED_CLAUSES,
    term_ok,TYPE_def,STATE_def,LET_DEF] \\ METIS_TAC []);

val raconv_thm = prove(
  ``!tm1 tm2 env.
      STATE s defs /\ TERM defs tm1 /\ TERM defs tm2 /\
      EVERY (\(v1,v2). TERM defs v1 /\ TERM defs v2) env ==>
      (raconv env tm1 tm2 = RACONV
         (MAP (\(v1,v2). (hol_tm v1, hol_tm v2)) env) (hol_tm tm1, hol_tm tm2))``,
  Induct THEN1
   (REVERSE (Cases_on `tm2`) \\ ONCE_REWRITE_TAC [raconv_def]
    \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
    THEN1 (Cases_on `h` \\ FULL_SIMP_TAC std_ss [RACONV,hol_tm_def])
    THEN1 (FULL_SIMP_TAC std_ss [RACONV,hol_tm_def])
    THEN1 (SRW_TAC [] [RACONV,hol_tm_def])
    \\ REPEAT STRIP_TAC \\ IMP_RES_TAC alphavars_thm
    \\ FULL_SIMP_TAC std_ss [hol_tm_def,RACONV])
  THEN1
   (Cases_on `tm2` \\ SIMP_TAC (srw_ss()) [Once raconv_def,hol_tm_def,RACONV]
    \\ SRW_TAC [] [RACONV,domain,hol_ty_def]
    \\ IMP_RES_TAC TERM
    \\ FULL_SIMP_TAC std_ss [BASIC_TYPE]
    \\ IMP_RES_TAC Equal_type
    \\ IMP_RES_TAC Select_type
    \\ FULL_SIMP_TAC (srw_ss()) [codomain]
    \\ TRY (METIS_TAC [TYPE_11])
    \\ CCONTR_TAC \\ FULL_SIMP_TAC std_ss []
    \\ IMP_RES_TAC Equal_type
    \\ IMP_RES_TAC Select_type
    \\ FULL_SIMP_TAC (srw_ss()) [codomain]
    \\ Cases_on `h`
    \\ FULL_SIMP_TAC (srw_ss()) [RACONV,domain,hol_ty_def,hol_tm_def])
  THEN1
   (Cases_on `tm2` \\ SIMP_TAC (srw_ss()) [Once raconv_def,hol_tm_def,RACONV]
    \\ SRW_TAC [] [RACONV] \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ TRY (Cases_on `h` \\ FULL_SIMP_TAC std_ss [RACONV,hol_tm_def] \\ NO_TAC))
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC Abs_Var
  \\ FULL_SIMP_TAC std_ss [hol_tm_def]
  \\ Cases_on `tm2` \\ SIMP_TAC (srw_ss()) [Once raconv_def,hol_tm_def,RACONV]
  \\ SRW_TAC [] [RACONV]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC Abs_Var
  \\ SRW_TAC [] [RACONV,hol_tm_def]
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
  \\ Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Abs (Var s4 ty4) t4)` []
  \\ Q.PAT_ASSUM `!tm2.bbb` (MP_TAC o Q.SPECL
        [`t4`,`((Var s' ty,Var s4 ty4)::env)`])
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF]
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC
  THEN1 (REPEAT STRIP_TAC \\ MATCH_MP_TAC TERM_Var \\ FULL_SIMP_TAC std_ss [])
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [MAP,hol_tm_def]
  \\ `(hol_ty ty = hol_ty ty4) = (ty = ty4)` by ALL_TAC THEN1
    (MATCH_MP_TAC TYPE_11 \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC std_ss [])

val aconv_thm = store_thm("aconv_thm",
  ``!tm1 tm2 env.
      STATE s defs /\ TERM defs tm1 /\ TERM defs tm2 ==>
      (aconv tm1 tm2 = ACONV (hol_tm tm1) (hol_tm tm2))``,
  SIMP_TAC std_ss [aconv_def,ACONV] \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC (raconv_thm |> Q.SPECL [`t1`,`t2`,`[]`]
       |> SIMP_RULE std_ss [EVERY_DEF,MAP])
  \\ FULL_SIMP_TAC std_ss []);

val is_term_thm = store_thm("is_term_thm",
  ``(is_var tm = ?n ty. tm = Var n ty) /\
    (is_const tm = ?n ty. tm = Const n ty) /\
    (is_abs tm = ?v x. tm = Abs v x) /\
    (is_comb tm = ?x y. tm = Comb x y)``,
  Cases_on `tm` \\ EVAL_TAC \\ FULL_SIMP_TAC std_ss []);

val mk_var_thm = store_thm("mk_var_thm",
  ``STATE s defs /\ TYPE defs ty ==> TERM defs (mk_var(v,ty))``,
  SIMP_TAC std_ss [mk_var_def] \\ METIS_TAC [TERM_Var]);

val mk_abs_thm = store_thm("mk_abs_thm",
  ``!res.
      TERM defs bvar /\ TERM defs bod /\ (mk_abs(bvar,bod) s = (res,s1)) ==>
      (s1 = s) /\ !t. (res = HolRes t) ==> TERM defs t /\ (t = Abs bvar bod)``,
  FULL_SIMP_TAC std_ss [mk_abs_def] \\ Cases_on `bvar`
  \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def,failwith_def]
  \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,
       WELLTYPED_CLAUSES,term_ok]);

val mk_comb_thm = prove(
  ``TERM defs f /\ TERM defs a /\ STATE s defs /\
    (mk_comb(f,a)s = (res,s1)) ==>
    (s1 = s) /\ !t. (res = HolRes t) ==> TERM defs t /\ (t = Comb f a)``,
  SIMP_TAC std_ss [mk_comb_def,ex_bind_def] \\ STRIP_TAC
  \\ MP_TAC (type_of_thm |> SIMP_RULE std_ss [] |> Q.SPEC `f`)
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC \\ FULL_SIMP_TAC (srw_ss()) []
  \\ MP_TAC (type_of_thm |> SIMP_RULE std_ss [] |> Q.SPEC `a`)
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Q.PAT_ASSUM `xxx = (res,s1)` (ASSUME_TAC o GSYM)
  \\ Cases_on `term_type f` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `s' = "fun"` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `l` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `t` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `t'` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `term_type a = h`
  \\ FULL_SIMP_TAC (srw_ss()) [failwith_def,ex_return_def]
  \\ IMP_RES_TAC term_type
  \\ FULL_SIMP_TAC (srw_ss()) [TERM_def,welltyped_in,WELLTYPED_CLAUSES,
       hol_tm_def,term_ok,hol_ty_def,LENGTH,type_INJ]
  \\ NTAC 4 (POP_ASSUM MP_TAC)
  \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def] \\ METIS_TAC []);

val dest_var_thm = store_thm("dest_var_thm",
  ``TERM defs v /\ STATE s defs ==>
    (dest_var v s = (res,s')) ==>
    (s' = s) /\ !n ty. (res = HolRes (n,ty)) ==> TYPE defs ty``,
  Cases_on `v`
  \\ SIMP_TAC (srw_ss()) [dest_var_def,ex_return_def,Once EQ_SYM_EQ,failwith_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM);

val dest_const_thm = store_thm("dest_const_thm",
  ``TERM defs v /\ STATE s defs ==>
    (dest_const v s = (res,s')) ==>
    (s' = s) /\ !n ty. (res = HolRes (n,ty)) ==> TYPE defs ty``,
  Cases_on `v`
  \\ SIMP_TAC (srw_ss()) [dest_const_def,ex_return_def,Once EQ_SYM_EQ,failwith_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM);

val dest_comb_thm = store_thm("dest_comb_thm",
  ``TERM defs v /\ STATE s defs ==>
    (dest_comb v s = (res,s')) ==>
    (s' = s) /\ !x y. (res = HolRes (x,y)) ==> TERM defs x /\ TERM defs y``,
  Cases_on `v`
  \\ SIMP_TAC (srw_ss()) [dest_comb_def,ex_return_def,Once EQ_SYM_EQ,failwith_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM);

val dest_abs_thm = store_thm("dest_abs_thm",
  ``TERM defs v /\ STATE s defs ==>
    (dest_abs v s = (res,s')) ==>
    (s' = s) /\ !x y. (res = HolRes (x,y)) ==> TERM defs x /\ TERM defs y``,
  Cases_on `v`
  \\ SIMP_TAC (srw_ss()) [dest_abs_def,ex_return_def,Once EQ_SYM_EQ,failwith_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC Abs_Var
  \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC TERM
  \\ IMP_RES_TAC TERM_Var \\ FULL_SIMP_TAC std_ss []);

val rator_thm = store_thm("rator_thm",
  ``TERM defs v /\ STATE s defs ==>
    (rator v s = (res,s')) ==>
    (s' = s) /\ !x. (res = HolRes x) ==> TERM defs x``,
  Cases_on `v`
  \\ SIMP_TAC (srw_ss()) [rator_def,ex_return_def,Once EQ_SYM_EQ,failwith_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM);

val rand_thm = store_thm("rand_thm",
  ``TERM defs v /\ STATE s defs ==>
    (rand v s = (res,s')) ==>
    (s' = s) /\ !x. (res = HolRes x) ==> TERM defs x``,
  Cases_on `v`
  \\ SIMP_TAC (srw_ss()) [rand_def,ex_return_def,Once EQ_SYM_EQ,failwith_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM);

val type_subst_bool = prove(
  ``type_subst i bool_ty = bool_ty``,
  SIMP_TAC (srw_ss()) [Once type_subst_def,LET_DEF]);

val type_subst_fun = prove(
  ``type_subst i (fun ty1 ty2) = fun (type_subst i ty1) (type_subst i ty2)``,
  SIMP_TAC (srw_ss()) [Once type_subst_def,LET_DEF] \\ SRW_TAC [] []);

val TERM_Const_type_subst = prove(
  ``EVERY (\(x,y). TYPE defs x /\ TYPE defs y) theta /\
    TERM defs (Const name a) ==> TERM defs (Const name (type_subst theta a))``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC TERM
  \\ IMP_RES_TAC type_subst_thm
  \\ FULL_SIMP_TAC std_ss [welltyped_in,hol_tm_def]
  \\ Cases_on `name = "="` \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC Equal_type \\ FULL_SIMP_TAC std_ss [type_subst_fun,type_subst_bool]
  THEN1 (FULL_SIMP_TAC (srw_ss()) [TERM_def,hol_tm_def,hol_ty_def,
      domain,welltyped_in, WELLTYPED_CLAUSES,term_ok,TYPE_def,type_ok_Fun])
  \\ Cases_on `name = "@"` \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC Select_type \\ FULL_SIMP_TAC std_ss [type_subst_fun,type_subst_bool]
  THEN1 (FULL_SIMP_TAC (srw_ss()) [TERM_def,hol_tm_def,hol_ty_def,codomain,
      domain,welltyped_in, WELLTYPED_CLAUSES,term_ok,TYPE_def,type_ok_Fun])
  \\ FULL_SIMP_TAC (srw_ss()) [TERM_def,hol_tm_def,hol_ty_def,codomain,
       domain,welltyped_in, WELLTYPED_CLAUSES,term_ok,TYPE_def,type_ok_Fun]
  \\ Q.EXISTS_TAC `ty2` \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [type_subst_thm]
  \\ Q.ABBREV_TAC `tt = (MAP (\(n,t). (hol_ty n,hol_ty t)) theta)`
  \\ Q.PAT_ASSUM `TYPE_SUBST i ty2 = hol_ty a` (ASSUME_TAC o GSYM)
  \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC [TYPE_SUBST_TWICE]);

val type_ok_CONS = prove(
  ``!a. type_ok defs a ==> type_ok (d::defs) a``,
  HO_MATCH_MP_TAC type_INDUCT_ALT \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [type_ok_CASES]
  \\ SIMP_TAC std_ss [type_INJ,type_DISTINCT]
  \\ FULL_SIMP_TAC std_ss [type_ok_Fun]
  \\ POP_ASSUM MP_TAC
  \\ SIMP_TAC std_ss [type_INJ,type_DISTINCT,Once type_ok_CASES]
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM]
  \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [types,FLAT,MAP,MEM_APPEND]);

val context_ok_IMP_type_ok = prove(
  ``!defs. context_ok defs /\ MEM (name,a) (consts defs) ==> type_ok defs a``,
  Induct \\ FULL_SIMP_TAC std_ss [consts,MAP,FLAT,MEM]
  \\ HO_MATCH_MP_TAC def_INDUCT \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [context_ok,consts_aux,APPEND]
  THEN1 (MATCH_MP_TAC type_ok_CONS \\ ASM_SIMP_TAC std_ss [])
  THEN1 (FULL_SIMP_TAC std_ss [MEM] \\ FULL_SIMP_TAC std_ss [type_ok_CONS]
         \\ FULL_SIMP_TAC std_ss [def_ok]
         \\ METIS_TAC [term_ok_IMP_type_ok,type_ok_CONS])
  \\ FULL_SIMP_TAC std_ss [MEM] \\ FULL_SIMP_TAC std_ss [type_ok_CONS]
  \\ FULL_SIMP_TAC std_ss [type_ok_Fun]
  \\ FULL_SIMP_TAC std_ss [def_ok,domain,codomain]
  \\ IMP_RES_TAC term_ok_IMP_type_ok
  \\ POP_ASSUM MP_TAC \\ FULL_SIMP_TAC std_ss [type_ok_Fun,type_ok_CONS]
  \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [type_ok_CASES]
  \\ SIMP_TAC std_ss [type_INJ,type_DISTINCT,LENGTH_MAP,MEM_MAP,PULL_EXISTS]
  \\ REPEAT STRIP_TAC
  \\ TRY (ONCE_REWRITE_TAC [type_ok_CASES] \\ SIMP_TAC std_ss [type_INJ] \\ NO_TAC)
  \\ FULL_SIMP_TAC std_ss [types,MAP,types_aux,FLAT,MEM,MEM_APPEND]
  \\ FULL_SIMP_TAC std_ss [LENGTH_STRING_SORT,ALL_DISTINCT_tvars]);

val mk_const_thm = store_thm("mk_const_thm",
  ``!name theta s z s'.
      STATE s defs /\ EVERY (\(x,y). TYPE defs x /\ TYPE defs y) theta /\
      (mk_const (name,theta) s = (z,s')) ==> (s' = s) /\
      !i. (z = HolRes i) ==> TERM defs i``,
  SIMP_TAC std_ss [mk_const_def,try_def,ex_bind_def,otherwise_def]
  \\ NTAC 3 STRIP_TAC \\ Cases_on `get_const_type name s`
  \\ IMP_RES_TAC get_const_type_thm
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def,ex_return_def]
  \\ SRW_TAC [] [ex_return_def]
  \\ MATCH_MP_TAC TERM_Const_type_subst \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,STATE_def,LET_DEF,term_ok,
       hol_tm_def]
  \\ Cases_on `name = "="` \\ FULL_SIMP_TAC std_ss [] THEN1
   (FULL_SIMP_TAC std_ss [MEM,MEM_APPEND,MAP_APPEND,
      MAP,ALL_DISTINCT_APPEND,MEM_MAP,PULL_EXISTS] \\ RES_TAC
    \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,domain,
         WELLTYPED_CLAUSES,term_ok,hol_ty_def,mk_vartype_def]
    \\ ONCE_REWRITE_TAC [type_ok_CASES]
    \\ FULL_SIMP_TAC (srw_ss()) [type_INJ])
  \\ Cases_on `name = "@"` \\ FULL_SIMP_TAC std_ss [] THEN1
   (FULL_SIMP_TAC std_ss [MEM,MEM_APPEND,MAP_APPEND,
      MAP,ALL_DISTINCT_APPEND,MEM_MAP,PULL_EXISTS] \\ RES_TAC
    \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,domain,codomain,
         WELLTYPED_CLAUSES,term_ok,hol_ty_def,mk_vartype_def]
    \\ ONCE_REWRITE_TAC [type_ok_CASES]
    \\ FULL_SIMP_TAC (srw_ss()) [type_INJ])
  \\ FULL_SIMP_TAC std_ss [WELLTYPED_CLAUSES,term_ok]
  \\ SIMP_TAC std_ss [PULL_EXISTS]
  \\ Q.PAT_ASSUM `defs = r.the_definitions` ASSUME_TAC
  \\ FULL_SIMP_TAC std_ss [MEM_APPEND,MEM,MAP,MEM_MAP,EXISTS_PROD]
  \\ FULL_SIMP_TAC std_ss [PULL_EXISTS]
  \\ Q.LIST_EXISTS_TAC [`[]`,`a`] \\ FULL_SIMP_TAC std_ss [TYPE_SUBST_EMPTY]
  \\ MATCH_MP_TAC context_ok_IMP_type_ok
  \\ FULL_SIMP_TAC std_ss [MEM_MAP,EXISTS_PROD] \\ METIS_TAC []);

val mk_const_eq = prove(
  ``STATE s defs ==>
    (mk_const ("=",[]) s =
     (HolRes (Const "=" (fun aty (fun aty bool_ty))),s))``,
  SIMP_TAC std_ss [mk_const_def,ex_bind_def,try_def,otherwise_def]
  \\ Cases_on `get_const_type "=" s` \\ STRIP_TAC
  \\ IMP_RES_TAC get_const_type_thm
  \\ REVERSE (Cases_on `q`) \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ POP_ASSUM MP_TAC \\ POP_ASSUM MP_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [STATE_def,LET_DEF,MEM_APPEND,MEM,ex_return_def]
  THEN1 (METIS_TAC [])
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [ALL_DISTINCT_APPEND,MEM,
       MEM_MAP,PULL_EXISTS,MAP,MAP_APPEND] \\ RES_TAC \\ FULL_SIMP_TAC std_ss []
  \\ NTAC 50 (SIMP_TAC (srw_ss())
      [Once type_subst_def,LET_DEF,rev_assocd_def,mk_vartype_def]));

val mk_eq_lemma = prove(
  ``inst [(term_type x,aty)] (Const "=" (fun aty (fun aty bool_ty))) s =
    ex_return
        (Const "="
           (fun (term_type x) (fun (term_type x) bool_ty))) s``,
  SIMP_TAC (srw_ss()) [inst_def,inst_aux_def,LET_DEF]
  \\ NTAC 50 (SIMP_TAC (srw_ss()) [Once type_subst_def,LET_DEF,mk_vartype_def,
       rev_assocd_def]) \\ SRW_TAC [] [] \\ METIS_TAC []);

val mk_eq_thm = store_thm("mk_eq_thm",
  ``TERM defs x /\ TERM defs y /\ STATE s defs ==>
    (mk_eq(x,y)s = (res,s')) ==>
    (s' = s) /\ !t. (res = HolRes t) ==>
    (t = Comb (Comb (Const "=" (fun (term_type x)
                               (fun (term_type x) bool_ty))) x) y) /\
    TERM defs t``,
  STRIP_TAC \\ SIMP_TAC std_ss [mk_eq_def,try_def,ex_bind_def,
    otherwise_def,mk_vartype_def]
  \\ MP_TAC (type_of_thm |> SIMP_RULE std_ss [] |> Q.SPEC `x`)
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC \\ FULL_SIMP_TAC (srw_ss()) []
  \\ IMP_RES_TAC mk_const_eq \\ FULL_SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC (srw_ss()) [mk_eq_lemma,ex_return_def]
  \\ Cases_on `mk_comb (Const "=" (fun (term_type x) (fun (term_type x) bool_ty)),x) s`
  \\ `TERM defs (Const "=" (fun (term_type x) (fun (term_type x) bool_ty)))` by
   (IMP_RES_TAC term_type
    \\ FULL_SIMP_TAC (srw_ss()) [TERM_def,hol_tm_def,welltyped_in,
      hol_ty_def,domain,term_ok,WELLTYPED_CLAUSES,TYPE_def] \\ METIS_TAC [])
  \\ Q.ABBREV_TAC `eq = (Const "=" (fun (term_type x) (fun (term_type x) bool_ty)))`
  \\ MP_TAC (mk_comb_thm |> Q.INST [`f`|->`eq`,`a`|->`x`,`res`|->`q`,`s1`|->`r`])
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
  \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `mk_comb (Comb eq x,y) s`
  \\ MP_TAC (mk_comb_thm |> Q.INST [`f`|->`Comb eq x`,`a`|->`y`,
      `res`|->`q`,`s1`|->`r'`])
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ FULL_SIMP_TAC std_ss []);

val dest_eq_thm = store_thm("dest_eq_thm",
  ``TERM defs tm /\ STATE s defs /\ (dest_eq tm s = (res, s')) ==>
    (s' = s) /\ !t1 t2. (res = HolRes (t1,t2)) ==> TERM defs t1 /\ TERM defs t2``,
  ONCE_REWRITE_TAC [EQ_SYM_EQ] \\ SIMP_TAC std_ss [dest_eq_def]
  \\ Cases_on `tm` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ Cases_on `h'` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ SRW_TAC [] [] \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []);

val MEM_term_union = prove(
  ``!l1 l2 x. MEM x (term_union l1 l2) ==> MEM x l1 \/ MEM x l2``,
  Induct \\ ONCE_REWRITE_TAC [term_union_def] \\ SIMP_TAC (srw_ss()) [LET_DEF]
  \\ SRW_TAC [] [] \\ RES_TAC \\ FULL_SIMP_TAC std_ss []);

val term_union_thm = prove(
  ``!l l'.
      EVERY (TERM defs) l /\ EVERY (TERM defs) l' /\ STATE s defs ==>
      (MAP hol_tm (term_union l l') = TERM_UNION (MAP hol_tm l) (MAP hol_tm l'))``,
  Induct \\ SIMP_TAC (srw_ss()) [TERM_UNION,MAP,Once term_union_def,LET_DEF]
  \\ REPEAT STRIP_TAC
  \\ `EXISTS (aconv h) (term_union l l') =
      EXISTS (ACONV (hol_tm h)) (TERM_UNION (MAP hol_tm l) (MAP hol_tm l'))` by
        ALL_TAC THEN1
   (RES_TAC \\ POP_ASSUM (K ALL_TAC)
    \\ POP_ASSUM (fn th => SIMP_TAC std_ss [Once (GSYM th)])
    \\ SIMP_TAC std_ss [EXISTS_MEM,MEM_MAP,PULL_EXISTS]
    \\ REPEAT STRIP_TAC \\ EQ_TAC \\ REPEAT STRIP_TAC
    \\ IMP_RES_TAC MEM_term_union
    \\ FULL_SIMP_TAC std_ss [EVERY_MEM] \\ RES_TAC
    \\ METIS_TAC [aconv_thm])
  \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] []);

val vfree_in_thm = prove(
  ``!y. TERM defs y /\ TYPE defs ty /\ STATE s defs ==>
        (VFREE_IN (Var name (hol_ty ty)) (hol_tm y) = vfree_in (Var name ty) y)``,
  Induct THEN1
   (FULL_SIMP_TAC std_ss [VFREE_IN,hol_tm_def,term_INJ]
    \\ ONCE_REWRITE_TAC [vfree_in_def] \\ SIMP_TAC (srw_ss()) []
    \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM
    \\ IMP_RES_TAC TYPE_11 \\ METIS_TAC [])
  THEN1
   (FULL_SIMP_TAC std_ss [VFREE_IN,hol_tm_def,term_INJ] \\ SRW_TAC [] []
    \\ FULL_SIMP_TAC std_ss [VFREE_IN,hol_tm_def,term_INJ,term_DISTINCT]
    \\ ONCE_REWRITE_TAC [vfree_in_def] \\ SIMP_TAC (srw_ss()) [])
  THEN1
   (REPEAT STRIP_TAC \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ FULL_SIMP_TAC std_ss [hol_tm_def,VFREE_IN] \\ REPEAT STRIP_TAC
    \\ ONCE_REWRITE_TAC [EQ_SYM_EQ] \\ SIMP_TAC (srw_ss()) [Once vfree_in_def])
  THEN1
   (REPEAT STRIP_TAC \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ FULL_SIMP_TAC std_ss [hol_tm_def,VFREE_IN] \\ REPEAT STRIP_TAC
    \\ ONCE_REWRITE_TAC [EQ_SYM_EQ] \\ SIMP_TAC (srw_ss()) [Once vfree_in_def]
    \\ IMP_RES_TAC Abs_Var
    \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,VFREE_IN,term_INJ]
    \\ IMP_RES_TAC TERM
    \\ FULL_SIMP_TAC std_ss []
    \\ METIS_TAC [TYPE_11]));

val VFREE_IN_IMP = prove(
  ``!y. TERM defs y /\ TYPE defs ty /\ STATE s defs /\
        VFREE_IN (Var name (hol_ty ty)) (hol_tm y) ==>
        vfree_in (Var name ty) y``,
  METIS_TAC [vfree_in_thm]);

val SELECT_LEMMA = prove(
  ``(@f. !s s'. f (s',s) <=> s <> t) = (\(z,y). y <> t)``,
  Q.ABBREV_TAC `p = (@f. !s s'. f (s',s) <=> s <> t)`
  \\ `?f. !s s'. f (s',s) <=> s <> t` by ALL_TAC
  THEN1 (Q.EXISTS_TAC `(\(z,y). y <> t)` \\ FULL_SIMP_TAC std_ss [])
  \\ `!s s'. p (s',s) <=> s <> t` by METIS_TAC []
  \\ FULL_SIMP_TAC std_ss [FUN_EQ_THM,FORALL_PROD]);

val SELECT_LEMMA2 = prove(
  ``(@f.
       !s s''.
         f (s'',s) <=>
         VFREE_IN (Var s' (hol_ty ty)) s'' /\ VFREE_IN s (hol_tm tm')) =
    (\(x,y). VFREE_IN (Var s' (hol_ty ty)) x /\ VFREE_IN y (hol_tm tm'))``,
  Q.ABBREV_TAC `p = (@f. !s s''. f (s'',s) <=>
         VFREE_IN (Var s' (hol_ty ty)) s'' /\ VFREE_IN s (hol_tm tm'))`
  \\ `?f. !s s''. f (s'',s) <=>
         VFREE_IN (Var s' (hol_ty ty)) s'' /\ VFREE_IN s (hol_tm tm')` by ALL_TAC
  THEN1 (Q.EXISTS_TAC `(\(s'',s). VFREE_IN (Var s' (hol_ty ty)) s'' /\
                VFREE_IN s (hol_tm tm'))` \\ FULL_SIMP_TAC std_ss [])
  \\ `!s s''. p (s'',s) <=> VFREE_IN (Var s' (hol_ty ty)) s'' /\
                            VFREE_IN s (hol_tm tm')` by METIS_TAC []
  \\ FULL_SIMP_TAC std_ss [FUN_EQ_THM,FORALL_PROD]);

val is_var_thm = prove(
  ``!x. is_var x = ?v ty. x = Var v ty``,
  Cases \\ FULL_SIMP_TAC (srw_ss()) [is_var_def]);

val VSUBST_EMPTY = prove(
  ``(!tm. VSUBST [] tm = tm)``,
  HO_MATCH_MP_TAC term_INDUCT
  \\ FULL_SIMP_TAC (srw_ss()) [VSUBST,REV_ASSOCD,EVERY_DEF,FILTER]);

val variant_thm = prove(
  ``!xs v x name.
      TERM defs x /\ TYPE defs ty /\ STATE s defs /\
      (xs = [x]) /\ (v = (Var name ty)) ==>
      (variant xs (Var name ty) =
       Var (VARIANT (hol_tm x) name (hol_ty ty)) ty)``,
  REWRITE_TAC [VARIANT,PRIME_CHAR] \\ HO_MATCH_MP_TAC variant_ind
  \\ SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ ASM_SIMP_TAC (srw_ss()) [Once variant_def,EXISTS_DEF]
  \\ MP_TAC (Q.SPEC `x` vfree_in_thm) \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [EXISTS_DEF]
  \\ REVERSE (Cases_on `vfree_in (Var name ty) x`)
  \\ FULL_SIMP_TAC (srw_ss()) [] THEN1
   (MP_TAC (VARIANT_PRIMES |> Q.SPECL [`hol_tm x`,`name`,`hol_ty ty`])
    \\ Cases_on `VARIANT_PRIMES (hol_tm x) name (hol_ty ty)`
    THEN1 FULL_SIMP_TAC (srw_ss()) [rich_listTheory.REPLICATE]
    \\ REPEAT STRIP_TAC \\ POP_ASSUM (MP_TAC o Q.SPEC `0`)
    \\ FULL_SIMP_TAC (srw_ss()) [rich_listTheory.REPLICATE])
  \\ MP_TAC (VARIANT_PRIMES |> Q.SPECL [`hol_tm x`,`name`,`hol_ty ty`])
  \\ Cases_on `VARIANT_PRIMES (hol_tm x) name (hol_ty ty)`
  \\ FULL_SIMP_TAC (srw_ss()) [rich_listTheory.REPLICATE,PRIME_CHAR]
  \\ REPEAT STRIP_TAC
  \\ `!m. m < n ==>
         VFREE_IN (Var (STRCAT name (REPLICATE (SUC m) #"'")) (hol_ty ty))
           (hol_tm x)` by ALL_TAC
  THEN1 (REPEAT STRIP_TAC \\ `SUC m < SUC n` by DECIDE_TAC \\ RES_TAC)
  \\ FULL_SIMP_TAC (srw_ss()) [rich_listTheory.REPLICATE,PRIME_CHAR]
  \\ MP_TAC (VARIANT_PRIMES |> Q.SPECL [`hol_tm x`,`STRCAT name "'"`,`hol_ty ty`])
  \\ FULL_SIMP_TAC std_ss [GSYM APPEND_ASSOC,APPEND]
  \\ Cases_on `VARIANT_PRIMES (hol_tm x) (STRCAT name "'") (hol_ty ty) = n`
  \\ FULL_SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC
  \\ `VARIANT_PRIMES (hol_tm x) (STRCAT name "'") (hol_ty ty) < n \/
      n < VARIANT_PRIMES (hol_tm x) (STRCAT name "'") (hol_ty ty)` by DECIDE_TAC
  \\ RES_TAC \\ FULL_SIMP_TAC std_ss [PRIME_CHAR])
  |> SIMP_RULE std_ss [] |> SPEC_ALL;

val TERM_Abs = prove(
  ``TERM defs (Abs (Var v ty) tm) = TYPE defs ty /\ TERM defs tm``,
  SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED_CLAUSES,
    term_ok,TYPE_def,AC CONJ_ASSOC CONJ_COMM]);

val TERM_Var_SIMP = prove(
  ``STATE s defs ==> (TERM defs (Var n ty) = TYPE defs ty)``,
  SIMP_TAC std_ss [TERM_def,TYPE_def,hol_tm_def,welltyped_in,
     WELLTYPED_CLAUSES,term_ok,STATE_def,LET_DEF]);

val vsubst_aux_thm = prove(
  ``!t tm theta. EVERY (\(t1,t2). TERM defs t1 /\ TERM defs t2 /\
                     (term_type t1 = term_type t2) /\ is_var t2) theta /\
    TERM defs tm /\ STATE s defs /\
    (vsubst_aux theta tm = t) ==>
    TERM defs t /\
    (hol_tm t = VSUBST (MAP (\(t1,t2). (hol_tm t1, hol_tm t2)) theta) (hol_tm tm))``,
  SIMP_TAC std_ss [] \\ Induct THEN1
   (NTAC 4 STRIP_TAC \\ SIMP_TAC (srw_ss()) [Once vsubst_aux_def]
    \\ SIMP_TAC (srw_ss()) [Once vsubst_aux_def,VSUBST,hol_tm_def]
    \\ Induct_on `theta` \\ FULL_SIMP_TAC std_ss []
    \\ ONCE_REWRITE_TAC [rev_assocd_def]
    \\ FULL_SIMP_TAC (srw_ss()) [EVERY_DEF,REV_ASSOCD,hol_tm_def]
    \\ Cases \\ FULL_SIMP_TAC (srw_ss()) [REV_ASSOCD]
    \\ Cases_on `r = Var s' h` \\ FULL_SIMP_TAC std_ss []
    THEN1 (FULL_SIMP_TAC std_ss [hol_tm_def])
    \\ REPEAT STRIP_TAC \\ SRW_TAC [] [] \\ METIS_TAC [TERM_11,hol_tm_def])
  THEN1
   (NTAC 4 STRIP_TAC \\ SIMP_TAC (srw_ss()) [Once vsubst_aux_def]
    \\ SIMP_TAC (srw_ss()) [Once vsubst_aux_def,VSUBST,hol_tm_def]
    \\ SRW_TAC [] [VSUBST])
  THEN1
   (STRIP_TAC \\ REPEAT (Q.PAT_ASSUM `!theta. bbb` (ASSUME_TAC o SPEC_ALL))
    \\ ONCE_REWRITE_TAC [vsubst_aux_def] \\ SIMP_TAC (srw_ss()) [LET_DEF]
    \\ FULL_SIMP_TAC std_ss [hol_tm_def,VSUBST,term_INJ]
    \\ REVERSE (REPEAT STRIP_TAC)
    \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,term_ok,hol_tm_def]
    \\ SIMP_TAC std_ss [GSYM VSUBST]
    \\ MATCH_MP_TAC VSUBST_WELLTYPED
    \\ FULL_SIMP_TAC std_ss [MEM_MAP,PULL_EXISTS,FORALL_PROD,EVERY_MEM]
    \\ REPEAT STRIP_TAC \\ RES_TAC \\ FULL_SIMP_TAC std_ss [is_var_thm]
    \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,term_INJ]
    \\ IMP_RES_TAC (REWRITE_RULE [TERM_def,welltyped_in] term_type)
    \\ NTAC 6 (POP_ASSUM MP_TAC)
    \\ FULL_SIMP_TAC std_ss [EVAL ``term_type (Var v ty)``]
    \\ ONCE_REWRITE_TAC [EQ_SYM_EQ] \\ FULL_SIMP_TAC std_ss []
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [WELLTYPED])
  \\ STRIP_TAC
  \\ ONCE_REWRITE_TAC [vsubst_aux_def] \\ SIMP_TAC (srw_ss()) [LET_DEF]
  \\ STRIP_TAC \\ IMP_RES_TAC Abs_Var
  \\ FULL_SIMP_TAC (srw_ss()) [is_var_def,hol_tm_def]
  \\ Cases_on `FILTER (\(t,x). x <> Var s' ty) theta = []`
  \\ FULL_SIMP_TAC std_ss [hol_tm_def] THEN1
   (SIMP_TAC std_ss [REWRITE_RULE[SELECT_LEMMA]VSUBST]
    \\ `(FILTER (\(z,y). y <> Var s' (hol_ty ty))
         (MAP (\(t1,t2). (hol_tm t1,hol_tm t2)) theta)) = []` by ALL_TAC THEN1
     (POP_ASSUM MP_TAC \\ REPEAT (POP_ASSUM (K ALL_TAC))
      \\ Induct_on `theta` \\ FULL_SIMP_TAC std_ss [MAP,FILTER]
      \\ Cases \\ FULL_SIMP_TAC std_ss [MAP,FILTER]
      \\ Cases_on `r = Var s' ty` \\ FULL_SIMP_TAC std_ss []
      \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def])
    \\ FULL_SIMP_TAC (srw_ss()) [VSUBST_EMPTY])
  \\ SIMP_TAC std_ss [SELECT_LEMMA2]
  \\ `EXISTS
       (@f.
          !s s''.
            f (s'',s) <=>
            VFREE_IN (Var s' (hol_ty ty)) s'' /\ VFREE_IN s (hol_tm tm'))
       (FILTER (\(z,y). y <> Var s' (hol_ty ty))
          (MAP (\(t1,t2). (hol_tm t1,hol_tm t2)) theta)) =
      EXISTS (\(t,x). vfree_in (Var s' ty) t /\ vfree_in x tm')
        (FILTER (\(t,x). x <> Var s' ty) theta)` by ALL_TAC THEN1
   (FULL_SIMP_TAC std_ss [SELECT_LEMMA2,EXISTS_MEM,MEM_FILTER,MEM_MAP,
      PULL_EXISTS,EXISTS_PROD,EVERY_MEM,FORALL_PROD] \\ REPEAT STRIP_TAC
    \\ EQ_TAC \\ REPEAT STRIP_TAC \\ RES_TAC THEN1
     (Cases_on `p_2'` \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
      \\ Q.MATCH_ASSUM_RENAME_TAC `MEM (pp,Var nn h1) theta` []
      \\ Q.LIST_EXISTS_TAC [`pp`,`Var nn h1`]
      \\ IMP_RES_TAC TERM \\ IMP_RES_TAC TYPE \\ IMP_RES_TAC vfree_in_thm
      \\ FULL_SIMP_TAC (srw_ss()) [term_INJ] \\ METIS_TAC [TYPE_11])
    \\ Cases_on `p_2` \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
    \\ Q.MATCH_ASSUM_RENAME_TAC `MEM (pp,Var nn h1) theta` []
    \\ Q.LIST_EXISTS_TAC [`pp`,`Var nn h1`]
    \\ IMP_RES_TAC TERM \\ IMP_RES_TAC TYPE \\ IMP_RES_TAC vfree_in_thm
    \\ FULL_SIMP_TAC (srw_ss()) [term_INJ,hol_tm_def] \\ METIS_TAC [TYPE_11])
  \\ REVERSE (Cases_on `EXISTS (\(t,x). vfree_in (Var s' ty) t /\ vfree_in x tm')
       (FILTER (\(t,x). x <> Var s' ty) theta)`) THEN1
   (IMP_RES_TAC TERM \\ IMP_RES_TAC TERM_Var \\ FULL_SIMP_TAC std_ss []
    \\ ASM_SIMP_TAC std_ss [REWRITE_RULE[SELECT_LEMMA]VSUBST]
    \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,WELLTYPED_CLAUSES,
        term_ok] \\ Q.PAT_ASSUM `!theta. bbb` (MP_TAC o Q.SPEC
          `FILTER (\(t,x). x <> Var s' ty) theta`)
    \\ Q.PAT_ASSUM `EVERY PP theta` (fn th => ASSUME_TAC th THEN MP_TAC th)
    \\ SIMP_TAC std_ss [EVERY_MEM,MEM_FILTER] \\ STRIP_TAC
    \\ REPEAT STRIP_TAC \\ AP_TERM_TAC \\ AP_THM_TAC \\ AP_TERM_TAC
    \\ Q.PAT_ASSUM `EVERY PP xx` MP_TAC
    \\ Q.SPEC_TAC (`theta`,`xs`) \\ Induct
    \\ SIMP_TAC std_ss [MEM,FILTER,MAP] \\ Cases
    \\ FULL_SIMP_TAC std_ss [EVERY_DEF] \\ STRIP_TAC
    \\ SRW_TAC [] []
    \\ METIS_TAC [TERM_11,TERM_def,welltyped_in,hol_tm_def])
  \\ ASM_SIMP_TAC std_ss [REWRITE_RULE[SELECT_LEMMA]VSUBST]
  \\ FULL_SIMP_TAC std_ss [hol_tm_def]
  \\ `TERM defs (vsubst_aux (FILTER (\(t,x). x <> Var s' ty) theta) tm') /\
      TYPE defs ty` by ALL_TAC THEN1
   (IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
    \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `FILTER (\(t,x). x <> Var s' ty) theta`)
    \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_FILTER])
  \\ IMP_RES_TAC variant_thm \\ FULL_SIMP_TAC std_ss []
  \\ POP_ASSUM (K ALL_TAC) \\ POP_ASSUM (K ALL_TAC)
  \\ FULL_SIMP_TAC std_ss [hol_tm_def,term_INJ]
  \\ `(hol_tm (vsubst_aux (FILTER (\ (t,x). x <> Var s' ty) theta) tm')) =
      (VSUBST
       (FILTER ( \ (z,y). y <> Var s' (hol_ty ty))
         (MAP ( \ (t1,t2). (hol_tm t1,hol_tm t2)) theta)) (hol_tm tm'))` by ALL_TAC
  THEN1
   (Q.PAT_ASSUM `!theta.bbb` (MP_TAC o
        Q.SPEC `FILTER (\(t,x). x <> Var s' ty) theta`)
    \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1
     (IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss []
      \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_FILTER,PULL_EXISTS])
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
    \\ AP_THM_TAC \\ AP_TERM_TAC
    \\ Q.PAT_ASSUM `EVERY PP xx` MP_TAC
    \\ Q.SPEC_TAC (`theta`,`xs`) \\ Induct
    \\ SIMP_TAC std_ss [MEM,FILTER,MAP] \\ Cases
    \\ FULL_SIMP_TAC std_ss [EVERY_DEF] \\ STRIP_TAC
    \\ SRW_TAC [] []
    \\ METIS_TAC [TERM_11,TERM_def,welltyped_in,hol_tm_def])
  \\ FULL_SIMP_TAC std_ss [TERM_Abs]
  \\ Q.ABBREV_TAC `theta1 = ((Var
          (VARIANT
             (VSUBST
                (FILTER (\(z,y). y <> Var s' (hol_ty ty))
                   (MAP (\(t1,t2). (hol_tm t1,hol_tm t2)) theta))
                (hol_tm tm')) s' (hol_ty ty)) ty,Var s' ty)::
           FILTER (\(t,x). x <> Var s' ty) theta)`
  \\ Q.PAT_ASSUM `!xx.bbb` (MP_TAC o Q.SPEC `theta1`)
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1
   (Q.UNABBREV_TAC `theta1` \\ IMP_RES_TAC TERM_Var_SIMP
    \\ FULL_SIMP_TAC std_ss [EVERY_DEF]
    \\ FULL_SIMP_TAC (srw_ss()) [EVERY_MEM,MEM_FILTER,PULL_EXISTS]
    \\ ONCE_REWRITE_TAC [term_type_def] \\ SIMP_TAC (srw_ss()) [])
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ AP_THM_TAC \\ AP_TERM_TAC \\ Q.UNABBREV_TAC `theta1`
  \\ FULL_SIMP_TAC (srw_ss()) [MAP,hol_tm_def,term_INJ]
  \\ Q.PAT_ASSUM `EVERY PP xx` MP_TAC
  \\ Q.SPEC_TAC (`theta`,`xs`) \\ Induct
  \\ SIMP_TAC std_ss [MEM,FILTER,MAP] \\ Cases
  \\ FULL_SIMP_TAC std_ss [EVERY_DEF] \\ STRIP_TAC
  \\ SRW_TAC [] []
  \\ METIS_TAC [TERM_11,TERM_def,welltyped_in,hol_tm_def]);

val forall_thm = prove(
  ``!f s (xs:(hol_term # hol_term) list). (forall f xs s = (res,s')) ==>
    (!x. ?r. f x s = (r,s)) ==>
    (s' = s) /\ ((res = HolRes T) ==> EVERY (\x. FST (f x s) = HolRes T) xs)``,
  STRIP_TAC \\ STRIP_TAC
  \\ Induct \\ ASM_SIMP_TAC (srw_ss()) [Once forall_def,ex_return_def,ex_bind_def]
  \\ STRIP_TAC \\ Cases_on `f h s` \\ SIMP_TAC std_ss [Once EQ_SYM_EQ]
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [] \\ STRIP_TAC \\ STRIP_TAC
  \\ `r = s` by METIS_TAC [PAIR,PAIR_EQ] \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `a` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC [FST,PAIR]);

val assoc_state = prove(
  ``!xs x. ?r. assoc x xs s = (r,s)``,
  Induct \\ ONCE_REWRITE_TAC [assoc_def] \\ TRY Cases
  \\ FULL_SIMP_TAC (srw_ss()) [failwith_def,ex_return_def] \\ SRW_TAC [] []);

val type_of_state = prove(
  ``!tm. ?r. type_of tm s = (r,s)``,
  HO_MATCH_MP_TAC type_of_ind \\ REPEAT STRIP_TAC
  \\ SIMP_TAC std_ss [Once type_of_def] \\ Cases_on `tm`
  \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def,failwith_def,ex_bind_def]
  THEN1
   (TRY (Cases_on `r`) \\ FULL_SIMP_TAC (srw_ss()) [dest_type_def]
    \\ TRY (Cases_on `a`)
    \\ FULL_SIMP_TAC (srw_ss()) [dest_type_def,failwith_def,ex_return_def]
    \\ Cases_on `l` \\ FULL_SIMP_TAC (srw_ss()) []
    \\ Cases_on `t` \\ FULL_SIMP_TAC (srw_ss()) [])
  \\ TRY (Cases_on `h`) \\ FULL_SIMP_TAC (srw_ss()) [dest_type_def]
  \\ TRY (Cases_on `r`) \\ FULL_SIMP_TAC (srw_ss()) [dest_type_def]
  \\ FULL_SIMP_TAC (srw_ss()) [mk_fun_ty_def,mk_type_def,ex_bind_def,
        try_def,otherwise_def,get_type_arity_def,
        get_the_type_constants_def,failwith_def,ex_return_def]
  \\ STRIP_ASSUME_TAC (assoc_state |> ISPEC ``s.the_type_constants``
        |> ISPEC ``"fun"``) \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `r` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ SRW_TAC [] []);

val term_type_Var = prove(
  ``term_type (Var v ty) = ty``,
  SIMP_TAC (srw_ss()) [Once term_type_def]);

val vsubst_thm = store_thm("vsubst_thm",
  ``EVERY (\(t1,t2). TERM defs t1 /\ TERM defs t2) theta /\
    TERM defs tm /\ STATE s defs /\
    (vsubst theta tm s = (res, s')) ==>
    (s' = s) /\ !t. (res = HolRes t) ==> TERM defs t /\
    (hol_tm t = VSUBST (MAP (\(t1,t2). (hol_tm t1, hol_tm t2)) theta) (hol_tm tm)) /\
    (EVERY (\(p_1,p_2). ?x ty. (hol_tm p_2 = Var x ty) /\
                               has_type (hol_tm p_1) ty) theta)``,
  ONCE_REWRITE_TAC [EQ_SYM_EQ] \\ SIMP_TAC std_ss [vsubst_def]
  \\ Cases_on `theta = []`
  \\ FULL_SIMP_TAC (srw_ss()) [MAP,VSUBST_EMPTY,ex_return_def,ex_bind_def]
  \\ Q.ABBREV_TAC `test = (\(t,x) state.
        case type_of t state of
          (HolRes ty,state) =>
            (case dest_var x state of
               (HolRes vty,state) => (HolRes (ty = SND vty),state)
             | (HolErr e,state) => (HolErr e,state))
        | (HolErr e,state) => (HolErr e,state))`
  \\ Cases_on `forall test theta s`
  \\ MP_TAC (forall_thm |> Q.SPECL [`test`,`s`,`theta`] |> Q.GENL [`res`,`s'`])
  \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `TERM defs tm /\ STATE s defs` \\ FULL_SIMP_TAC std_ss []
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1
   (Q.UNABBREV_TAC `test` \\ FULL_SIMP_TAC std_ss [FORALL_PROD]
    \\ REPEAT STRIP_TAC \\ STRIP_ASSUME_TAC (Q.SPEC `p_1` type_of_state)
    \\ Cases_on `r'` \\ FULL_SIMP_TAC (srw_ss()) []
    \\ Cases_on `p_2`
    \\ FULL_SIMP_TAC (srw_ss()) [dest_var_def,ex_return_def,failwith_def])
  \\ STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Cases_on `a` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ STRIP_TAC \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ `EVERY
       (\(t1,t2).
          TERM defs t1 /\ TERM defs t2 /\
          (term_type t1 = term_type t2) /\ is_var t2) theta` by ALL_TAC THEN1
   (FULL_SIMP_TAC std_ss [EVERY_MEM,FORALL_PROD] \\ NTAC 3 STRIP_TAC \\ RES_TAC
    \\ FULL_SIMP_TAC std_ss []
    \\ Q.UNABBREV_TAC `test`
    \\ FULL_SIMP_TAC std_ss []
    \\ IMP_RES_TAC type_of_thm
    \\ FULL_SIMP_TAC (srw_ss()) [dest_var_def]
    \\ Cases_on `p_2`
    \\ FULL_SIMP_TAC (srw_ss()) [dest_var_def,ex_return_def,failwith_def,is_var_def]
    \\ SIMP_TAC (srw_ss()) [Once term_type_def])
  \\ IMP_RES_TAC (vsubst_aux_thm |> SIMP_RULE std_ss [])
  \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM,FORALL_PROD] \\ REPEAT STRIP_TAC \\ RES_TAC
  \\ Cases_on `p_2` \\ FULL_SIMP_TAC (srw_ss()) [is_var_def,hol_tm_def,term_INJ]
  \\ IMP_RES_TAC term_type
  \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def,typeof]
  \\ FULL_SIMP_TAC std_ss [WELLTYPED,term_type_Var] \\ METIS_TAC []);

val rev_assocd_thm = prove(
  ``rev_assocd = REV_ASSOCD``,
  SIMP_TAC std_ss [FUN_EQ_THM] \\ Induct_on `x'`
  \\ ONCE_REWRITE_TAC [rev_assocd_def] \\ SRW_TAC [] [REV_ASSOCD]
  \\ Cases_on `h` \\ SRW_TAC [] [REV_ASSOCD]);

val inst_aux_Var = prove(
  ``inst_aux [] theta (Var v ty) state =
      (HolRes (Var v (type_subst theta ty)),state)``,
  SIMP_TAC (srw_ss()) [Once inst_aux_def,rev_assocd_thm,REV_ASSOCD,
       LET_DEF,ex_return_def] \\ METIS_TAC []);

val inst_aux_thm = prove(
  ``!env theta tm s s' res.
      EVERY (\(t1,t2). TYPE defs t1 /\ TYPE defs t2) theta /\
      EVERY (\(t1,t2). TERM defs t1 /\ TERM defs t2) env /\
      TERM defs tm /\ STATE s defs /\
      (inst_aux env theta tm s = (res, s')) ==>
      STATE s' defs /\
      case res of
      | HolRes t =>
         (INST_ALT (MAP (\(t1,t2). (hol_tm t1, hol_tm t2)) env)
           (MAP (\(t1,t2). (hol_ty t1, hol_ty t2)) theta) (hol_tm tm) =
           Result (hol_tm t))
      | HolErr v =>
         (INST_ALT (MAP (\(t1,t2). (hol_tm t1, hol_tm t2)) env)
           (MAP (\(t1,t2). (hol_ty t1, hol_ty t2)) theta) (hol_tm tm) =
           Clash (hol_tm s'.the_clash_var))``,

  HO_MATCH_MP_TAC inst_aux_ind \\ NTAC 4 STRIP_TAC \\ Cases_on `tm`
  \\ FULL_SIMP_TAC (srw_ss()) []
  THEN1
   (ONCE_REWRITE_TAC [inst_aux_def] \\ SIMP_TAC (srw_ss()) [LET_DEF]
    \\ `(if type_subst theta h = h then Var s h
      else Var s (type_subst theta h)) = Var s (type_subst theta h)` by METIS_TAC []
    \\ FULL_SIMP_TAC std_ss [rev_assocd_thm] \\ POP_ASSUM (K ALL_TAC)
    \\ SIMP_TAC std_ss [INST_ALT,hol_tm_def]
    \\ FULL_SIMP_TAC (srw_ss()) [GSYM type_subst_thm,ex_return_def]
    \\ SIMP_TAC std_ss [GSYM AND_IMP_INTRO] \\ NTAC 7 STRIP_TAC
    \\ `(REV_ASSOCD (Var s (hol_ty (type_subst theta h)))
           (MAP (\(t1,t2). (hol_tm t1,hol_tm t2)) env)
           (Var s (hol_ty h)) =
         Var s (hol_ty h)) =
       (REV_ASSOCD (Var s (type_subst theta h)) env (Var s h) = Var s h)`
          by ALL_TAC THEN1
     (Induct_on `env` \\ FULL_SIMP_TAC std_ss [MAP,REV_ASSOCD]
      \\ Cases \\ FULL_SIMP_TAC std_ss [MAP,REV_ASSOCD,EVERY_DEF] \\ STRIP_TAC
      \\ `(hol_tm r = hol_tm (Var s (type_subst theta h))) =
          (r = Var s (type_subst theta h))` by ALL_TAC THEN1
       (MATCH_MP_TAC (TERM_11 |> GEN_ALL)
        \\ Q.LIST_EXISTS_TAC [`s'`,`defs`]
        \\ FULL_SIMP_TAC std_ss []
        \\ MATCH_MP_TAC (TERM_Var |> GEN_ALL)
        \\ Q.LIST_EXISTS_TAC [`s'`] \\ FULL_SIMP_TAC std_ss []
        \\ FULL_SIMP_TAC std_ss [TYPE_def,type_subst_thm]
        \\ MATCH_MP_TAC type_ok_TYPE_SUBST
        \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss [TYPE_def,
             EVERY_MEM,FORALL_PROD,MEM_MAP,PULL_EXISTS] \\ METIS_TAC [])
      \\ FULL_SIMP_TAC std_ss [hol_tm_def]
      \\ Cases_on `r = Var s (type_subst theta h)`
      \\ FULL_SIMP_TAC std_ss [hol_tm_def,EVERY_DEF]
      \\ SIMP_TAC std_ss [GSYM hol_tm_def]
      \\ MATCH_MP_TAC (TERM_11 |> GEN_ALL)
      \\ Q.LIST_EXISTS_TAC [`s'`,`defs`]
      \\ FULL_SIMP_TAC std_ss [])
    \\ FULL_SIMP_TAC std_ss []
    \\ Q.SPEC_TAC (`res`,`res`)
    \\ Cases_on `REV_ASSOCD (Var s (type_subst theta h)) env (Var s h) = Var s h`
    \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,ex_bind_def,
         set_the_clash_var_def,failwith_def]
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
    \\ POP_ASSUM (ASSUME_TAC o GSYM)
    \\ FULL_SIMP_TAC (srw_ss()) [STATE_def,hol_tm_def,LET_DEF]
    \\ Q.PAT_ASSUM `defs = s'.the_definitions` ASSUME_TAC
    \\ FULL_SIMP_TAC (srw_ss()) [MAP_APPEND]
    \\ Q.PAT_ASSUM `ALL_DISTINCT (MAP FST s'.the_type_constants)` MP_TAC
    \\ FULL_SIMP_TAC (srw_ss()) [MAP_APPEND] \\ REPEAT STRIP_TAC
    \\ MATCH_MP_TAC (TERM_Var |> GEN_ALL)
    \\ Q.EXISTS_TAC `s'`
    \\ STRIP_TAC
    THEN1 (FULL_SIMP_TAC (srw_ss()) [STATE_def,LET_DEF,MAP_APPEND] \\ METIS_TAC [])
    \\ FULL_SIMP_TAC std_ss [TYPE_def,type_subst_thm]
    \\ MATCH_MP_TAC type_ok_TYPE_SUBST \\ IMP_RES_TAC TERM
    \\ FULL_SIMP_TAC std_ss [TYPE_def]
    \\ FULL_SIMP_TAC std_ss [TYPE_def,
             EVERY_MEM,FORALL_PROD,MEM_MAP,PULL_EXISTS] \\ METIS_TAC [])
  THEN1
   (ONCE_REWRITE_TAC [inst_aux_def] \\ SIMP_TAC (srw_ss()) [LET_DEF,ex_return_def]
    \\ NTAC 4 STRIP_TAC
    \\ `(res = HolRes (Const s (type_subst theta h))) /\ (s' = s'')` by ALL_TAC
    THEN1 (Cases_on `type_subst theta h = h` \\ FULL_SIMP_TAC std_ss [])
    \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
    \\ Cases_on `s = "="` \\ FULL_SIMP_TAC std_ss [] THEN1
     (IMP_RES_TAC Equal_type
      \\ FULL_SIMP_TAC (srw_ss()) [type_subst_fun,type_subst_bool]
      \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,domain]
      \\ SIMP_TAC std_ss [INST_ALT,type_subst_thm])
    \\ Cases_on `s = "@"` \\ FULL_SIMP_TAC std_ss [] THEN1
     (IMP_RES_TAC Select_type
      \\ FULL_SIMP_TAC (srw_ss()) [type_subst_fun,type_subst_bool]
      \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,domain,codomain]
      \\ SIMP_TAC std_ss [INST_ALT,type_subst_thm])
    \\ SIMP_TAC std_ss [INST_ALT,type_subst_thm])
  THEN1
   (ONCE_REWRITE_TAC [inst_aux_def]
    \\ FULL_SIMP_TAC (srw_ss()) [LET_DEF,ex_return_def,ex_bind_def]
    \\ NTAC 4 STRIP_TAC \\ Cases_on `inst_aux env theta h s`
    \\ REVERSE (Cases_on `q`) \\ FULL_SIMP_TAC (srw_ss()) [] THEN1
     (Q.PAT_ASSUM `HolErr xx = res` (ASSUME_TAC o GSYM)
      \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
      \\ ONCE_REWRITE_TAC [INST_ALT] \\ IMP_RES_TAC TERM
      \\ FULL_SIMP_TAC std_ss []
      \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `s`)
      \\ FULL_SIMP_TAC (srw_ss()) [IS_CLASH])
    \\ Cases_on `inst_aux env theta h0 r`
    \\ REVERSE (Cases_on `q`) \\ FULL_SIMP_TAC (srw_ss()) [] THEN1
     (Q.PAT_ASSUM `HolErr xx = res` (ASSUME_TAC o GSYM)
      \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
      \\ ONCE_REWRITE_TAC [INST_ALT] \\ IMP_RES_TAC TERM
      \\ FULL_SIMP_TAC std_ss []
      \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `s`)
      \\ FULL_SIMP_TAC (srw_ss()) [IS_CLASH]
      \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `r`)
      \\ FULL_SIMP_TAC (srw_ss()) [IS_CLASH])
    THEN1
     (Q.PAT_ASSUM `HolRes xx = res` (ASSUME_TAC o GSYM)
      \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def]
      \\ ONCE_REWRITE_TAC [INST_ALT] \\ IMP_RES_TAC TERM
      \\ FULL_SIMP_TAC std_ss []
      \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `s`)
      \\ FULL_SIMP_TAC (srw_ss()) [IS_CLASH]
      \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `r`)
      \\ FULL_SIMP_TAC (srw_ss()) [IS_CLASH,RESULT]))
  \\ SIMP_TAC (srw_ss()) [Once inst_aux_def]
  \\ SIMP_TAC std_ss [GSYM AND_IMP_INTRO] \\ NTAC 7 STRIP_TAC
  \\ IMP_RES_TAC Abs_Var
  \\ Q.MATCH_ASSUM_RENAME_TAC `h = Var v ty` []
  \\ FULL_SIMP_TAC std_ss []
  \\ SIMP_TAC (srw_ss()) [Once inst_aux_def]
  \\ `!ty'. (if ty' = ty then Var v ty else Var v ty') = Var v ty'` by METIS_TAC []
  \\ FULL_SIMP_TAC std_ss [rev_assocd_thm,REV_ASSOCD,LET_DEF,ex_return_def]
  \\ SIMP_TAC (srw_ss()) [ex_bind_def,otherwise_def]
  \\ Cases_on `inst_aux ((Var v ty,Var v (type_subst theta ty))::env) theta h0 s`
  \\ Q.PAT_ASSUM `!x yy.bbb` (K ALL_TAC)
  \\ Q.PAT_ASSUM `!x yy.bbb` (MP_TAC o Q.SPECL
       [`((Var v ty,Var v (type_subst theta ty))::env)`,`s`])
  \\ FULL_SIMP_TAC std_ss []
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1
   (IMP_RES_TAC TERM \\ IMP_RES_TAC TERM_Var \\ FULL_SIMP_TAC std_ss [EVERY_DEF]
    \\ MATCH_MP_TAC TERM_Var \\ FULL_SIMP_TAC std_ss []
    \\ FULL_SIMP_TAC std_ss [TYPE_def,type_subst_thm]
    \\ MATCH_MP_TAC type_ok_TYPE_SUBST
    \\ FULL_SIMP_TAC std_ss [MEM_MAP,EXISTS_PROD,PULL_EXISTS,FORALL_PROD,
         EVERY_MEM] \\ METIS_TAC [])
  \\ STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [] THEN1
   (Q.SPEC_TAC (`res`,`res`) \\ FULL_SIMP_TAC (srw_ss()) []
    \\ SIMP_TAC std_ss [INST_ALT,hol_tm_def]
    \\ FULL_SIMP_TAC std_ss [hol_tm_def,type_subst_thm,IS_RESULT,RESULT]
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC (srw_ss()) [get_the_clash_var_def,failwith_def]
  \\ Cases_on `r.the_clash_var <> Var v (type_subst theta ty)`
  \\ `(r.the_clash_var = Var v (type_subst theta ty)) =
      (hol_tm r.the_clash_var =
       Var v (TYPE_SUBST (MAP (\(t1,t2). (hol_ty t1,hol_ty t2)) theta)
        (hol_ty ty)))` by ALL_TAC THEN1
   (SIMP_TAC std_ss [GSYM type_subst_thm,GSYM hol_tm_def]
    \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
    \\ MATCH_MP_TAC TERM_11 \\ FULL_SIMP_TAC std_ss []
    \\ STRIP_TAC THEN1
     (Q.PAT_ASSUM `STATE r defs` MP_TAC
      \\ SIMP_TAC std_ss [STATE_def,LET_DEF]
      \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [])
    \\ MATCH_MP_TAC TERM_Var \\ FULL_SIMP_TAC std_ss []
    \\ FULL_SIMP_TAC std_ss [TYPE_def,type_subst_thm]
    \\ MATCH_MP_TAC type_ok_TYPE_SUBST \\ IMP_RES_TAC TERM
    \\ FULL_SIMP_TAC std_ss [TYPE_def]
    \\ FULL_SIMP_TAC std_ss [TYPE_def,
             EVERY_MEM,FORALL_PROD,MEM_MAP,PULL_EXISTS] \\ METIS_TAC [])
  \\ FULL_SIMP_TAC (srw_ss()) [] THEN1
   (Q.SPEC_TAC (`res`,`res`) \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
    \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss []
    \\ SIMP_TAC std_ss [INST_ALT,hol_tm_def]
    \\ FULL_SIMP_TAC std_ss [hol_tm_def,type_subst_thm,IS_RESULT,CLASH])
  THEN1 (FULL_SIMP_TAC std_ss [type_subst_thm,hol_tm_def])
  \\ SIMP_TAC (srw_ss()) [inst_aux_Var,``dest_var (Var v ty) state``
        |> SIMP_CONV (srw_ss()) [dest_var_def,ex_return_def]]
  \\ Q.ABBREV_TAC `vvv = (VARIANT
                (RESULT
                   (INST_ALT []
                      (MAP ( \ (t1,t2). (hol_ty t1,hol_ty t2)) theta)
                      (hol_tm h0))) v
                (TYPE_SUBST
                   (MAP ( \ (t1,t2). (hol_ty t1,hol_ty t2)) theta)
                   (hol_ty ty)))`
  \\ `(variant (MAP (inst_var theta) (frees h0))
         (Var v (type_subst theta ty))) = Var vvv (type_subst theta ty)` by cheat
  \\ FULL_SIMP_TAC std_ss []
  \\ SIMP_TAC (srw_ss()) [inst_aux_Var,``dest_var (Var v ty) state``
        |> SIMP_CONV (srw_ss()) [dest_var_def,ex_return_def]]
  \\ Q.PAT_ASSUM `!x y z.bbb` (K ALL_TAC)
  \\ Q.PAT_ASSUM `!x y z.bbb` (MP_TAC o Q.SPECL
       [`((Var v ty,Var v (type_subst theta ty))::env)`,`vvv`,`ty`,`r`])
  \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `inst_aux ((Var v ty,Var v (type_subst theta ty))::env) theta
       (vsubst_aux [(Var vvv ty,Var v ty)] h0) r`
  \\ SIMP_TAC std_ss []
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1
   (FULL_SIMP_TAC std_ss [EVERY_DEF] \\ REPEAT STRIP_TAC
    \\ TRY (MATCH_MP_TAC TERM_Var) \\ IMP_RES_TAC TERM
    \\ FULL_SIMP_TAC std_ss [] THEN1
     (FULL_SIMP_TAC std_ss [TYPE_def,type_subst_thm]
      \\ MATCH_MP_TAC type_ok_TYPE_SUBST
      \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss [TYPE_def,
             EVERY_MEM,FORALL_PROD,MEM_MAP,PULL_EXISTS] \\ METIS_TAC [])
    \\ (vsubst_aux_thm |> SIMP_RULE std_ss []
     |> Q.SPECL [`tm`,`[Var v ty,Var y ty]`]
     |> SIMP_RULE std_ss [EVERY_DEF,MAP,hol_tm_def]
     |> UNDISCH_ALL |> CONJUNCT1 |> DISCH_ALL |> MATCH_MP_TAC)
    \\ ONCE_REWRITE_TAC [term_type_def]
    \\ FULL_SIMP_TAC (srw_ss()) [is_var_def]
    \\ REPEAT STRIP_TAC
    \\ TRY (MATCH_MP_TAC TERM_Var) \\ IMP_RES_TAC TERM
    \\ FULL_SIMP_TAC std_ss [])
  \\ STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [hol_tm_def,type_subst_thm]
  \\ SIMP_TAC std_ss [INST_ALT]
  \\ FULL_SIMP_TAC std_ss [hol_tm_def,type_subst_thm,IS_RESULT,CLASH]
  \\ FULL_SIMP_TAC std_ss [GSYM type_subst_thm]
  \\ `vvv = v` by cheat \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Q.SPEC_TAC (`res`,`res`) \\ FULL_SIMP_TAC (srw_ss()) []
  \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss [hol_tm_def]
  \\ `(hol_tm (vsubst_aux [(Var v ty,Var v ty)] h0)) =
      (VSUBST [(Var v (hol_ty ty),Var v (hol_ty ty))] (hol_tm h0))` by
   ((vsubst_aux_thm |> SIMP_RULE std_ss []
     |> Q.SPECL [`tm`,`[Var v ty,Var y ty]`]
     |> SIMP_RULE std_ss [EVERY_DEF,MAP,hol_tm_def]
     |> UNDISCH_ALL |> CONJUNCT2 |> DISCH_ALL |> MATCH_MP_TAC)
    \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC (srw_ss()) [is_var_def]
    \\ MATCH_MP_TAC TERM_Var \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC std_ss [IS_RESULT,RESULT]);

val inst_lemma = prove(
  ``EVERY (\(t1,t2). TYPE defs t1 /\ TYPE defs t2) theta /\
    TERM defs tm /\ STATE s defs /\
    (inst theta tm s = (res, s')) ==>
    STATE s' defs /\ !t. (res = HolRes t) ==>
    (hol_tm t = INST (MAP (\(t1,t2). (hol_ty t1, hol_ty t2)) theta) (hol_tm tm))``,
  SIMP_TAC std_ss [INST_DEF,inst_def] \\ Cases_on `theta = []`
  \\ ASM_SIMP_TAC std_ss [MAP,EVERY_DEF,ex_return_def] THEN1
   (Q.SPEC_TAC (`res`,`res`) \\ SIMP_TAC (srw_ss()) []
    \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in]
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
    \\ IMP_RES_TAC INST_CORE_HAS_TYPE
    \\ POP_ASSUM (MP_TAC o Q.SPECL [`[]`,`[]`])
    \\ FULL_SIMP_TAC std_ss [MEM,REV_ASSOCD]
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [RESULT]
    \\ FULL_SIMP_TAC std_ss [INST_ALT_EMPTY,result_INJ])
  \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC (inst_aux_thm |> Q.SPECL [`[]`,`theta`]
                  |> SIMP_RULE std_ss [EVERY_DEF,MAP])
  \\ REPEAT (Q.PAT_ASSUM `!x.bbb` (K ALL_TAC))
  \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC INST_CORE_HAS_TYPE
  \\ POP_ASSUM (MP_TAC o Q.SPECL
       [`(MAP (\(t1,t2). (hol_ty t1,hol_ty t2)) theta)`,`[]`])
  \\ FULL_SIMP_TAC std_ss [MEM,REV_ASSOCD] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [MAP,RESULT,result_DISTINCT,result_INJ]
  \\ Cases_on `res` \\ FULL_SIMP_TAC (srw_ss()) []);

val inst_thm = store_thm("inst_thm",
  ``EVERY (\(t1,t2). TYPE defs t1 /\ TYPE defs t2) theta /\
    TERM defs tm /\ STATE s defs /\
    (inst theta tm s = (res, s')) ==>
    STATE s' defs /\ !t. (res = HolRes t) ==> TERM defs t /\
    (hol_tm t = INST (MAP (\(t1,t2). (hol_ty t1, hol_ty t2)) theta) (hol_tm tm))``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC inst_lemma
  \\ FULL_SIMP_TAC std_ss [TERM_def,welltyped_in]
  \\ IMP_RES_TAC INST_CORE_LEMMA
  \\ SIMP_TAC std_ss [INST_DEF]
  \\ POP_ASSUM (MP_TAC o Q.SPEC `(MAP (\(t1,t2). (hol_ty t1,hol_ty t2)) theta)`)
  \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss [RESULT]
  \\ STRIP_TAC THEN1 METIS_TAC [welltyped]
  \\ MATCH_MP_TAC (INST_ALT_term_ok |> SPEC_ALL |> UNDISCH_ALL |> CONJUNCT1
       |> SPEC_ALL |> UNDISCH_ALL |> DISCH_ALL |> GEN_ALL
       |> REWRITE_RULE [AND_IMP_INTRO])
  \\ Q.LIST_EXISTS_TAC [`(MAP (\(t1,t2). (hol_ty t1,hol_ty t2)) theta)`,
       `hol_tm tm`,`[]`] \\ FULL_SIMP_TAC std_ss [MEM_MAP,PULL_EXISTS,FORALL_PROD]
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM,TYPE_def,FORALL_PROD]
  \\ METIS_TAC []);

(* ------------------------------------------------------------------------- *)
(* Verification of thm functions                                             *)
(* ------------------------------------------------------------------------- *)

val dest_thm_thm = store_thm("dest_thm_thm",
  ``THM defs th /\ STATE s defs /\ (dest_thm th = (asl, c)) ==>
    EVERY (TERM defs) asl /\ TERM defs c``,
  REPEAT STRIP_TAC \\ Cases_on `th` \\ IMP_RES_TAC THM
  \\ FULL_SIMP_TAC std_ss [dest_thm_def] \\ METIS_TAC []);

val hyp_thm = store_thm("hyp_thm",
  ``THM defs th /\ STATE s defs /\ (hyp th = asl) ==>
    EVERY (TERM defs) asl``,
  REPEAT STRIP_TAC \\ Cases_on `th` \\ IMP_RES_TAC THM
  \\ FULL_SIMP_TAC std_ss [hyp_def] \\ METIS_TAC []);

val concl_thm = store_thm("concl_thm",
  ``THM defs th /\ STATE s defs /\ (concl th = c) ==>
    TERM defs c``,
  REPEAT STRIP_TAC \\ Cases_on `th` \\ IMP_RES_TAC THM
  \\ FULL_SIMP_TAC std_ss [concl_def] \\ METIS_TAC []);

val REFL_thm = store_thm("REFL_thm",
  ``TERM defs tm /\ STATE s defs /\ (REFL tm s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  SIMP_TAC std_ss [REFL_def,ex_bind_def] \\ Cases_on `mk_eq(tm,tm) s`
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC mk_eq_thm
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ Q.PAT_ASSUM `xxx = th` (ASSUME_TAC o GSYM)
  \\ FULL_SIMP_TAC (srw_ss()) [THM_def,hol_tm_def,hol_ty_def,domain]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ DISJ1_TAC \\ Q.EXISTS_TAC `hol_tm tm`
  \\ STRIP_TAC \\ SIMP_TAC std_ss [equation]
  \\ IMP_RES_TAC term_type \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [TERM_def]);

val TRANS_thm = store_thm("TRANS_thm",
  ``THM defs th1 /\ THM defs th2 /\ STATE s defs /\
    (TRANS th1 th2 s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  Cases_on `th1` \\ Cases_on `th2` \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ SIMP_TAC std_ss [TRANS_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h''` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h'` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h'` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ SRW_TAC [] [ex_bind_def] \\ IMP_RES_TAC THM
  \\ Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Comb (Comb (Const "=" h1) ll) m1)` []
  \\ POP_ASSUM MP_TAC
  \\ Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Comb (Comb (Const "=" h2) m2) rr)` []
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM \\ Cases_on `mk_eq (ll,rr) s`
  \\ MP_TAC (mk_eq_thm |> Q.INST [`x`|->`ll`,`y`|->`rr`,`res`|->`q`,`s'`|->`r`])
  \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC TERM
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation]
  \\ IMP_RES_TAC Equal_type
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain]
  \\ `hol_ty (term_type ll) = typeof (hol_tm ll)` by
       (IMP_RES_TAC term_type \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC std_ss [term_INJ]
  \\ Q.LIST_EXISTS_TAC [`MAP hol_tm l`,`MAP hol_tm l'`,`(hol_tm m1)`,`(hol_tm m2)`]
  \\ FULL_SIMP_TAC std_ss []
  \\ MP_TAC (aconv_thm |> Q.SPECL [`m1`,`m2`] |> SIMP_RULE std_ss [])
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
  \\ IMP_RES_TAC Equal_type_IMP
  \\ FULL_SIMP_TAC std_ss []
  \\ MATCH_MP_TAC term_union_thm
  \\ FULL_SIMP_TAC std_ss []);

val MK_COMB_thm = store_thm("MK_COMB_thm",
  ``THM defs th1 /\ THM defs th2 /\ STATE s defs /\
    (MK_COMB (th1,th2) s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  Cases_on `th1` \\ Cases_on `th2` \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ SIMP_TAC std_ss [MK_COMB_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h''` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h'` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h'` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ SRW_TAC [] [ex_bind_def] \\ IMP_RES_TAC THM
  \\ Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Comb (Comb (Const "=" h1) f1) f2)` []
  \\ POP_ASSUM MP_TAC
  \\ Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Comb (Comb (Const "=" h2) x1) x2)` []
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM
  \\ Cases_on `mk_comb (f1,x1) s`
  \\ MP_TAC (mk_comb_thm |> Q.INST [`f`|->`f1`,`a`|->`x1`,`res`|->`q`,`s1`|->`r`])
  \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC TERM
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ Cases_on `mk_comb (f2,x2) s`
  \\ MP_TAC (mk_comb_thm |> Q.INST [`f`|->`f2`,`a`|->`x2`,`res`|->`q`,`s1`|->`r'`])
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ Cases_on `mk_eq (Comb f1 x1,Comb f2 x2) s`
  \\ MP_TAC (mk_eq_thm |> Q.INST [`x`|->`Comb f1 x1`,
         `y`|->`Comb f2 x2`,`res`|->`q`,`s'`|->`r''`])
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 2 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ Q.LIST_EXISTS_TAC [`MAP hol_tm l`,`MAP hol_tm l'`]
  \\ STRIP_TAC THEN1 (MATCH_MP_TAC term_union_thm \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC std_ss []
  \\ STRIP_TAC THEN1 (IMP_RES_TAC term_type \\ FULL_SIMP_TAC std_ss [hol_tm_def])
  \\ REVERSE (REPEAT STRIP_TAC)
  THEN1 (FULL_SIMP_TAC std_ss [TERM_def,welltyped_in,hol_tm_def])
  \\ IMP_RES_TAC Equal_type \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,domain]
  \\ IMP_RES_TAC Equal_type_IMP \\ FULL_SIMP_TAC std_ss []);

val ABS_thm = store_thm("ABS_thm",
  ``TERM defs tm /\ THM defs th1 /\ STATE s defs /\
    (ABS tm th1 s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  Cases_on `th1` \\ SIMP_TAC std_ss [ABS_def] \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h'` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ FULL_SIMP_TAC std_ss [ex_bind_def]
  \\ Cases_on `s'' = "="` \\ FULL_SIMP_TAC (srw_ss()) [] \\ SRW_TAC [] []
  \\ Q.MATCH_ASSUM_RENAME_TAC
       `THM defs (Sequent l (Comb (Comb (Const "=" h) t1) t2))` []
  \\ Cases_on `mk_abs (tm,t1) s` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ MP_TAC (mk_abs_thm |> Q.SPECL [`q`] |> Q.INST [`bvar`|->`tm`,
       `bod`|->`t1`,`s1`|->`r`])
  \\ IMP_RES_TAC THM \\ IMP_RES_TAC TERM \\ IMP_RES_TAC TERM
  \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Cases_on `mk_abs (tm,t2) s` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ MP_TAC (mk_abs_thm |> Q.SPECL [`q`] |> Q.INST [`bvar`|->`tm`,
       `bod`|->`t2`,`s1`|->`r'`])
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM
  \\ Cases_on `mk_eq (Abs tm t1,Abs tm t2) s`
  \\ MP_TAC (mk_eq_thm |> Q.INST [`x`|->`Abs tm t1`,`y`|->`Abs tm t2`,
                                  `res`|->`q`,`s'`|->`r''`])
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 3 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ SIMP_TAC (srw_ss()) [typeof]
  \\ IMP_RES_TAC Abs_Var \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [hol_tm_def,term_INJ]
  \\ SIMP_TAC (srw_ss()) [Once term_type_def,hol_ty_def,type_INJ]
  \\ IMP_RES_TAC Equal_type \\ FULL_SIMP_TAC (srw_ss()) []
  \\ IMP_RES_TAC Equal_type_IMP \\ FULL_SIMP_TAC (srw_ss()) [hol_ty_def,domain]
  \\ STRIP_TAC THEN1 (IMP_RES_TAC term_type \\ FULL_SIMP_TAC std_ss [])
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss [TYPE_def]
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_MAP,PULL_EXISTS]
  \\ REPEAT STRIP_TAC \\ RES_TAC
  \\ IMP_RES_TAC TERM \\ IMP_RES_TAC VFREE_IN_IMP);

val BETA_thm = store_thm("BETA_thm",
  ``TERM defs tm /\ STATE s defs /\
    (BETA tm s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  SIMP_TAC std_ss [BETA_def] \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ Cases_on `tm` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ SRW_TAC [] [ex_bind_def,ex_return_def]
  \\ IMP_RES_TAC TERM \\ IMP_RES_TAC Abs_Var
  \\ FULL_SIMP_TAC std_ss []
  \\ Q.MATCH_ASSUM_RENAME_TAC `t2 = Var name ty` [] \\ POP_ASSUM (K ALL_TAC)
  \\ Q.MATCH_ASSUM_RENAME_TAC `TERM defs (Abs (Var name ty) bod)` []
  \\ Cases_on `mk_eq (Comb (Abs (Var name ty) bod) (Var name ty),bod) s`
  \\ IMP_RES_TAC TERM
  \\ MP_TAC (mk_eq_thm |> Q.INST [`x`|->`Comb (Abs (Var name ty) bod) (Var name ty)`,
         `y`|->`bod`,`res`|->`q`,`s'`|->`r`])
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 4 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ SIMP_TAC (srw_ss()) [Once term_type_def]
  \\ SIMP_TAC (srw_ss()) [Once term_type_def,typeof]
  \\ FULL_SIMP_TAC std_ss [codomain]
  \\ IMP_RES_TAC term_type \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC TERM \\ FULL_SIMP_TAC std_ss [TYPE_def]
  \\ FULL_SIMP_TAC std_ss [TERM_def]);

val ASSUME_thm = store_thm("ASSUME_thm",
  ``TERM defs tm /\ STATE s defs /\
    (ASSUME tm s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  SIMP_TAC std_ss [ASSUME_def] \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ STRIP_TAC \\ MP_TAC (type_of_thm |> Q.SPEC `tm`)
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC (srw_ss()) [ex_bind_def]
  \\ MP_TAC (mk_type_thm |> Q.SPECL [`"bool"`,`[]`,`s`])
  \\ Cases_on `mk_type ("bool",[]) s`
  \\ FULL_SIMP_TAC (srw_ss()) [EVERY_DEF]
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `term_type tm = bool_ty`
  \\ FULL_SIMP_TAC (srw_ss()) [failwith_def,ex_return_def]
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 3 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ IMP_RES_TAC term_type
  \\ FULL_SIMP_TAC std_ss [TERM_def]
  \\ FULL_SIMP_TAC std_ss [welltyped_in,WELLTYPED]
  \\ NTAC 2 (POP_ASSUM MP_TAC)
  \\ FULL_SIMP_TAC std_ss [hol_ty_def]);

val EQ_MP_thm = store_thm("EQ_MP_thm",
  ``THM defs th1 /\ THM defs th2 /\ STATE s defs /\
    (EQ_MP th1 th2 s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  Cases_on `th1` \\ Cases_on `th2` \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ SIMP_TAC std_ss [EQ_MP_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h''` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ Cases_on `h` \\ FULL_SIMP_TAC (srw_ss()) [failwith_def]
  \\ SRW_TAC [] [ex_bind_def,ex_return_def] \\ IMP_RES_TAC THM
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC TERM
  \\ Q.MATCH_ASSUM_RENAME_TAC `THM defs (Sequent l
        (Comb (Comb (Const "=" h1) t1) t2))` []
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 6 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ Q.LIST_EXISTS_TAC [`MAP hol_tm l`,`MAP hol_tm l'`]
  \\ IMP_RES_TAC TERM \\ IMP_RES_TAC Equal_type
  \\ FULL_SIMP_TAC (srw_ss()) [domain,hol_ty_def]
  \\ IMP_RES_TAC Equal_type_IMP
  \\ FULL_SIMP_TAC (srw_ss()) [domain,hol_ty_def]
  \\ Q.LIST_EXISTS_TAC [`hol_tm t1`,`hol_tm h'`]
  \\ STRIP_TAC THEN1 (MATCH_MP_TAC term_union_thm \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC std_ss []
  \\ METIS_TAC [aconv_thm]);

val FILTER_ACONV = prove(
  ``STATE s defs /\ TERM defs tm /\ EVERY (TERM defs) l ==>
    (MAP hol_tm (FILTER (\t1. ~aconv tm t1) l) =
     FILTER ($~ o ACONV (hol_tm tm)) (MAP hol_tm l))``,
  Induct_on `l` \\ FULL_SIMP_TAC std_ss [EVERY_DEF,FILTER,MAP]
  \\ REPEAT STRIP_TAC \\ IMP_RES_TAC aconv_thm
  \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] []);

val DEDUCT_ANTISYM_RULE_thm = store_thm("DEDUCT_ANTISYM_RULE_thm",
  ``THM defs th1 /\ THM defs th2 /\ STATE s defs /\
    (DEDUCT_ANTISYM_RULE th1 th2 s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  Cases_on `th1` \\ Cases_on `th2` \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ SIMP_TAC std_ss [DEDUCT_ANTISYM_RULE_def,LET_DEF,ex_bind_def]
  \\ Cases_on `mk_eq (h,h') s` \\ STRIP_TAC
  \\ IMP_RES_TAC THM
  \\ MP_TAC (mk_eq_thm |> Q.INST [`x`|->`h`,
         `y`|->`h'`,`res`|->`q`,`s'`|->`r`])
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 7 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ Q.LIST_EXISTS_TAC [`MAP hol_tm l`,`MAP hol_tm l'`]
  \\ FULL_SIMP_TAC std_ss [term_remove_def]
  \\ REVERSE STRIP_TAC THEN1 (FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC term_type)
  \\ IMP_RES_TAC (GSYM FILTER_ACONV)
  \\ FULL_SIMP_TAC std_ss []
  \\ MATCH_MP_TAC term_union_thm
  \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [EVERY_MEM,MEM_FILTER]);

val INST_TYPE_thm = store_thm("INST_TYPE_thm",
  ``EVERY (\(t1,t2). TYPE defs t1 /\ TYPE defs t2) theta /\
    THM defs th1 /\ STATE s defs /\
    (INST_TYPE theta th1 s = (res, s')) ==>
    STATE s' defs /\ !th. (res = HolRes th) ==> THM defs th``,
  cheat);

val map_lemma = prove(
  ``!l P s res s'.
      (map (vsubst theta) l s = (res,s')) ==>
      EVERY (\x. ?r. (vsubst theta x s = (r,s)) /\
                     !t. (r = HolRes t) ==> P x t) l ==>
      (s' = s) /\ !ts. (res = HolRes ts) ==> EVERY2 P l ts``,
  Induct \\ SIMP_TAC (srw_ss()) [Once map_def,ex_return_def,ex_bind_def]
  \\ NTAC 5 STRIP_TAC \\ Cases_on `vsubst theta h s` \\ FULL_SIMP_TAC std_ss []
  \\ SIMP_TAC std_ss [Once EQ_SYM_EQ]
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Cases_on `r = s` \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `map (vsubst theta) l s`
  \\ NTAC 2 STRIP_TAC \\ RES_TAC
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []);

val INST_thm = store_thm("INST_thm",
  ``EVERY (\(t1,t2). TERM defs t1 /\ TERM defs t2) theta /\
    THM defs th1 /\ STATE s defs /\
    (INST theta th1 s = (res, s')) ==>
    (s' = s) /\ !th. (res = HolRes th) ==> THM defs th``,
  Cases_on `th1` \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ SIMP_TAC std_ss [hol_kernelTheory.INST_def,LET_DEF,ex_bind_def]
  \\ STRIP_TAC \\ IMP_RES_TAC THM
  \\ Cases_on `map (vsubst theta) l s`
  \\ MP_TAC (map_lemma |> Q.SPECL [`l`,`\tm t. (hol_tm t =
      VSUBST (MAP (\(t1,t2). (hol_tm t1,hol_tm t2)) theta) (hol_tm tm))`,`s`])
  \\ FULL_SIMP_TAC std_ss []
  \\ MATCH_MP_TAC IMP_IMP \\ STRIP_TAC THEN1
   (FULL_SIMP_TAC std_ss [EVERY_MEM] \\ REPEAT STRIP_TAC
    \\ Cases_on `vsubst theta x s` \\ FULL_SIMP_TAC std_ss [] \\ RES_TAC
    \\ IMP_RES_TAC (vsubst_thm |> SIMP_RULE std_ss [EVERY_MEM])
    \\ METIS_TAC [])
  \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) [ex_return_def]
  \\ Cases_on `vsubst theta h s`
  \\ MP_TAC (vsubst_thm |> Q.INST [`res`|->`q`,`s'`|->`r'`,`tm`|->`h`])
  \\ FULL_SIMP_TAC std_ss [] \\ STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC std_ss [THM_def]
  \\ SIMP_TAC (srw_ss()) [Once proves_CASES,term_INJ,type_INJ,term_DISTINCT]
  \\ NTAC 9 DISJ2_TAC \\ DISJ1_TAC
  \\ FULL_SIMP_TAC (srw_ss()) [hol_tm_def,hol_ty_def,domain,equation,term_INJ]
  \\ Q.LIST_EXISTS_TAC [`(MAP (\(t1,t2). (hol_tm t1,hol_tm t2)) theta)`,
       `MAP hol_tm l`,`hol_tm h`]
  \\ FULL_SIMP_TAC std_ss [MEM_MAP,EXISTS_PROD,PULL_EXISTS,EVERY_MEM,FORALL_PROD]
  \\ REVERSE STRIP_TAC THEN1
    (REPEAT STRIP_TAC \\ RES_TAC \\ FULL_SIMP_TAC std_ss [TERM_def] \\ METIS_TAC [])
  \\ Q.PAT_ASSUM `EVERY2 xxx yyy zzz` MP_TAC
  \\ Q.SPEC_TAC (`a`,`a`) \\ Q.SPEC_TAC (`l`,`l`)
  \\ Induct THEN1 (Cases \\ FULL_SIMP_TAC (srw_ss()) [])
  \\ STRIP_TAC \\ Cases THEN1 (FULL_SIMP_TAC (srw_ss()) [])
  \\ FULL_SIMP_TAC std_ss [EVERY2_def,MAP]);

(* ------------------------------------------------------------------------- *)
(* Verification of definition functions                                      *)
(* ------------------------------------------------------------------------- *)

(*
  new_axiom_def
  new_basic_definition_def
  new_basic_type_definition_def
*)

val _ = export_theory();
