open HolKernel boolLib bossLib lcsymtacs
open finite_mapTheory
open CompilerTheory compilerTerminationTheory toBytecodeProofsTheory compilerProofsTheory
val _ = new_theory"bootstrapProofs"

val env_rs_empty = store_thm("env_rs_empty",
  ``bs.stack = [] ∧ bs.clock = NONE ∧ rd.sm = [] ∧ rd.cls = FEMPTY ⇒
    env_rs [] [] [] init_compiler_state rd (ck,[]) bs``,
  simp[env_rs_def,init_compiler_state_def,intLangExtraTheory.good_cmap_def,FLOOKUP_UPDATE
      ,good_contab_def,IntLangTheory.tuple_cn_def,toIntLangProofsTheory.cmap_linv_def] >>
  simp[pmatchTheory.env_to_Cenv_MAP,intLangExtraTheory.all_vlabs_menv_def
      ,intLangExtraTheory.vlabs_menv_def,pred_setTheory.SUM_IMAGE_THM] >>
  strip_tac >>
  simp[Cenv_bs_def,env_renv_def,s_refs_def,good_rd_def,FEVERY_DEF])

(*
val call_decl_thm = store_thm("call_decl_thm",
``
  let code = (compile_decs init_compiler_state (decls++[Dlet (Pvar fname) (Fun arg body)]) []) in
  bs0.code = code ∧
  bs0.pc = 0 ∧
  bs0.stack = [] ∧
  bs0.clock = NONE
⇒
  ∃ptr env st str rf h.
  let cl = Block closure_tag [CodePtr ptr;env] in
  let bs1 = bs0 with <| pc := next_addr bs0.inst_length bs0.code
                      ; stack := cl::st (* or wherever fname is *)
                      ; output := str
                      ; refs := rf
                      ; handler := h
                      |> in
  bc_eval bs0 = SOME bs1 ∧
  refs_ok ?? rf ∧
  ∀bs ret mid arg cenv env v.
    bs.code = [CallPtr] ∧
    bs.pc = 0 ∧
    bs.stack = CodePtr ptr::env::arg::cl::mid++st ∧
    bs.handler = h ∧
    refs_ok ?? bs.refs ∧
    Cv_bv (v_to_Cv ??? (lookup "x" in env)) arg ∧ (* should be for everything in env, not just x *)
    evaluate [] cenv [] env (App Opapp (Var (Short fname)) (Var(Short "x"))) ([],Rval v)
    ⇒
    ∃bv rf'.
    let bs' = bs with <| stack := bv::mid++st
                       ; pc := next_addr bs.inst_length bs.code
                       ; refs := rf'
                       |> in
    refs_ok ?? rf' ∧
    bc_eval bs = SOME bs' ∧
    Cv_bv (v_to_Cv ??? v) bv
*)

val _ = export_theory()
