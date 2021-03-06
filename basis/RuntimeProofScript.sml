(*
  Proof about the exit function in the Runtime module.
*)
open preamble
     ml_translatorTheory ml_translatorLib ml_progLib cfLib basisFunctionsLib
     mlstringTheory runtimeFFITheory RuntimeProgTheory

val _ = new_theory"RuntimeProof";

val _ = translation_extends "RuntimeProg";
val _ = option_monadsyntax.temp_add_option_monadsyntax();

(* heap predicate for the (trivial) runtime state *)

val RUNTIME_def = Define `
  RUNTIME =
    IOx runtime_ffi_part ()`

Theorem RUNTIME_FFI_part_hprop
`FFI_part_hprop RUNTIME`
  (rw [RUNTIME_def,cfHeapsBaseTheory.IO_def,cfMainTheory.FFI_part_hprop_def,
      cfHeapsBaseTheory.IOx_def, runtime_ffi_part_def,
      set_sepTheory.SEP_CLAUSES,set_sepTheory.SEP_EXISTS_THM,
      set_sepTheory.cond_STAR ]
  \\ fs[set_sepTheory.one_def]);

val st = get_ml_prog_state();

Theorem Runtime_exit_spec
  `INT i iv ==>
   app (p:'ffi ffi_proj) ^(fetch_v "Runtime.exit" st) [iv]
     (RUNTIME)
     (POSTf n. λc b. RUNTIME * &(n = "exit" /\ c = [] /\ b = [i2w i]))`
  (strip_tac \\ xcf "Runtime.exit" st
  \\ xlet `POSTv wv. &WORD ((i2w i):word8) wv * RUNTIME`
  THEN1
   (simp[cf_wordFromInt_W8_def,cfTheory.app_wordFromInt_W8_def]
    \\ irule local_elim \\ reduce_tac
    \\ fs[ml_translatorTheory.INT_def] \\ xsimpl)
  \\ xlet `POSTv loc. RUNTIME * W8ARRAY loc [i2w i]`
  THEN1
   (simp[cf_aw8alloc_def]
    \\ irule local_elim \\ reduce_tac
    \\ fs[WORD_def] \\ simp[app_aw8alloc_def]
    \\ xsimpl \\ EVAL_TAC)
  \\ simp[cf_ffi_def,local_def]
  \\ rw[]
  \\ qexists_tac `RUNTIME * W8ARRAY loc [i2w i]`
  \\ qexists_tac `emp` \\ simp[app_ffi_def]
  \\ simp[GSYM PULL_EXISTS]
  \\ conj_tac
  >- (fs[STAR_def,emp_def,SPLIT_emp2] >> metis_tac[])
  \\ qexists_tac `(POSTf n. (λc b. RUNTIME * &(n = "exit" ∧ c = [] ∧ b = [i2w i]) * SEP_EXISTS loc. W8ARRAY loc [i2w i]))`
  \\ rw[]
  >- (fs[RUNTIME_def,runtime_ffi_part_def,IOx_def]
      \\ xsimpl
      \\ qmatch_goalsub_abbrev_tac `IO s u ns`
      \\ MAP_EVERY qexists_tac [`loc`,`[]`,`[i2w i]`,`emp`,`s`,`u`,`ns`]
      \\ conj_tac >- EVAL_TAC
      \\ conj_tac >- EVAL_TAC
      \\ unabbrev_all_tac
      \\ fs[mk_ffi_next_def,encode_def,decode_def,ffi_exit_def]
      \\ xsimpl \\ metis_tac[SEP_IMP_def])
  \\ xsimpl);

Theorem Runtime_abort_spec
  `app (p:'ffi ffi_proj) ^(fetch_v "Runtime.abort" st) [uv]
     (RUNTIME)
     (POSTf n. λc b. RUNTIME * &(n = "exit" /\ c = [] /\ b = [1w]))`
  (xcf "Runtime.abort" st
  \\ xapp
  \\ xsimpl \\ EVAL_TAC);

Theorem RUNTIME_HPROP_INJ[hprop_inj]
  `!cl1 cl2. HPROP_INJ (RUNTIME) (RUNTIME) (T)`
  (rw[HPROP_INJ_def,STAR_def,EQ_IMP_THM]
  THEN1 (asm_exists_tac \\ rw[] \\ rw[SPLIT_emp1,cond_def])
  \\ fs[SPLIT_emp1,cond_def] \\ metis_tac[]);

val _ = export_theory();
