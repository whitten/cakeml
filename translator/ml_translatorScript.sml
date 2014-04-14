open HolKernel Parse boolLib bossLib;
val _ = new_theory "ml_translator";
local open intLib in end;
open astTheory libTheory semanticPrimitivesTheory bigStepTheory;
open terminationTheory determTheory evalPropsTheory bigClockTheory;
open arithmeticTheory listTheory combinTheory pairTheory;
open integerTheory terminationTheory;
open lcsymtacs;

infix \\ val op \\ = op THEN;


(* Definitions *)

val Eval_def = Define `
  Eval env exp P =
    ?res. evaluate F env (0,empty_store) exp ((0,empty_store),Rval res) /\
          P (res:v)`;

val evaluate_closure_def = Define `
  evaluate_closure input cl output =
    ?env exp. (do_app ARB empty_store Opapp cl input = SOME (env,empty_store,exp)) /\
              evaluate F env (0,empty_store) exp ((0,empty_store),Rval (output))`;

val AppReturns_def = Define ` (* think of this as a Hoare triple {P} cl {Q} *)
  AppReturns P cl Q =
    !v. P v ==> ?u. evaluate_closure v cl u /\ Q u`;

val Arrow_def = Define `
  Arrow a b f =
    \v. !x. AppReturns (a x) v (b (f x))`;

val _ = overload_on ("-->",``Arrow``)

val Eq_def = Define `
  Eq (abs:'a->v->bool) x =
    (\y v. (x = y) /\ abs y v)`;

val And_def = Define `And a P x v = (P x /\ a (x:'a) (v:v))`;

val UNIT_TYPE_def = Define `
  UNIT_TYPE (u:unit) (v:v) = (v = Litv Unit)`;

val INT_def = Define `
  INT i = \v:v. (v = Litv (IntLit i))`;

val NUM_def = Define `
  NUM n = INT (& n)`;

val BOOL_def = Define `
  BOOL b = \v:v. (v = Litv (Bool b))`;

val CONTAINER_def = Define `CONTAINER x = x`;

val TAG_def = Define `TAG n x = x`;

val PRECONDITION_def = Define `PRECONDITION b = (b:bool)`;

val PreImp_def = Define `
  PreImp b1 b2 = (PRECONDITION b1 ==> b2)`;


(* Theorems *)

val evaluate_11_Rval = store_thm("evaluate_11_Rval",
  ``evaluate b env s exp (s1,Rval res1) ==>
    evaluate b env s exp (s2,Rval res2) ==> (res1 = res2)``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC big_exp_determ
  \\ FULL_SIMP_TAC (srw_ss()) []);

val Eval_Arrow = store_thm("Eval_Arrow",
  ``Eval env x1 ((a --> b) f) ==>
    Eval env x2 (a x) ==>
    Eval env (App Opapp x1 x2) (b (f x))``,
  SIMP_TAC std_ss [Eval_def,Arrow_def] \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC std_ss [AppReturns_def] \\ RES_TAC
  \\ FULL_SIMP_TAC std_ss [evaluate_closure_def]
  \\ Q.EXISTS_TAC `u` \\ FULL_SIMP_TAC std_ss []
  \\ Q.LIST_EXISTS_TAC [`res`,`res'`,`env'`]
  \\ FULL_SIMP_TAC (srw_ss()) [do_app_def]
  \\ Cases_on `res` \\ FULL_SIMP_TAC (srw_ss()) [do_app_def]
  \\ METIS_TAC []);

val write_def = Define `
  write name v ((menv,cenv,env):all_env) = (menv,cenv,(name,v)::env)`;

val Eval_Fun = store_thm("Eval_Fun",
  ``(!v x. a x v ==> Eval (write name v env) body (b ((f:'a->'b) x))) ==>
    Eval env (Fun name body) ((a --> b) f)``,
  SIMP_TAC std_ss [Eval_def,Arrow_def] \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC (srw_ss()) [AppReturns_def,Eval_def,do_app_def,
       bind_def,evaluate_closure_def,write_def]);

val Eval_Fun_Eq = store_thm("Eval_Fun_Eq",
  ``(!v. a x v ==> Eval (write name v env) body (b (f x))) ==>
    Eval env (Fun name body) ((Eq a x --> b) f)``,
  SIMP_TAC std_ss [Eval_def,Arrow_def] \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC (srw_ss()) [AppReturns_def,Eval_def,do_app_def,
       bind_def,evaluate_closure_def,write_def,Eq_def]);

val And_IMP_Eq = store_thm("And_IMP_Eq",
  ``Eval env exp ((And a P --> b) f) ==>
    (P x ==> Eval env exp ((Eq a x --> b) f))``,
  FULL_SIMP_TAC std_ss [Eval_def,Arrow_def,AppReturns_def,And_def,Eq_def]
  \\ METIS_TAC []);

val Eq_IMP_And = store_thm("Eq_IMP_And",
  ``(!x. P x ==> Eval env (Fun name exp) ((Eq a x --> b) f)) ==>
    Eval env (Fun name exp) ((And a P --> b) f)``,
  FULL_SIMP_TAC std_ss [Eval_def,Arrow_def,AppReturns_def,And_def,Eq_def]
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []);

val Eval_Fun_And = store_thm("Eval_Fun_And",
  ``(!v x. P x ==> a x v ==> Eval (write name v env) body (b (f x))) ==>
    Eval env (Fun name body) ((And a P --> b) f)``,
  FULL_SIMP_TAC std_ss [GSYM And_def,AND_IMP_INTRO]
  \\ REPEAT STRIP_TAC \\ MATCH_MP_TAC Eval_Fun \\ ASM_SIMP_TAC std_ss []);

val Eval_Let = store_thm("Eval_Let",
  ``Eval env exp (a res) /\
    (!v. a res v ==> Eval (write name v env) body (b (f res))) ==>
    Eval env (Let (SOME name) exp body) (b (LET f res))``,
  SIMP_TAC std_ss [Eval_def,Arrow_def] \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ RES_TAC \\ Q.EXISTS_TAC `res''` \\ FULL_SIMP_TAC std_ss [LET_DEF,opt_bind_def]
  \\ `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC std_ss []
  \\ Q.LIST_EXISTS_TAC [`res'`,`0,empty_store`]
  \\ FULL_SIMP_TAC std_ss [write_def]);

val lookup_var_def = Define `
  lookup_var name ((menv,cenv,env):all_env) = lookup name env`;

val lookup_cons_def = Define `
  lookup_cons name (env:all_env) = lookup name (SND (FST (SND env)))`;

val lookup_var_write = store_thm("lookup_var_write",
  ``lookup_var v (write w x env) =
    if v = w then SOME x else lookup_var v env``,
  PairCases_on `env`
  \\ SIMP_TAC std_ss [lookup_var_def,write_def,lookup_def]
  \\ METIS_TAC []);

val Eval_Var_SWAP_ENV = store_thm("Eval_Var_SWAP_ENV",
  ``!env1.
      Eval env1 (Var (Short name)) P /\
      (lookup_var name env = lookup_var name env1) ==>
      Eval env (Var (Short name)) P``,
  `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC std_ss [FORALL_PROD,lookup_var_def]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases,Eval_def, lookup_var_id_def]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases,Eval_def, lookup_var_id_def]);

val LOOKUP_VAR_def = Define `
  LOOKUP_VAR name (env:all_env) x = (lookup_var name env = SOME x)`;

val LOOKUP_VAR_THM = store_thm("LOOKUP_VAR_THM",
  ``LOOKUP_VAR name env x ==> Eval env (Var (Short name)) ($= x)``,
  `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC std_ss [FORALL_PROD,lookup_var_def]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases,Eval_def,LOOKUP_VAR_def,
       lookup_var_id_def,lookup_var_def]);

val LOOKUP_VAR_SIMP = store_thm("LOOKUP_VAR_SIMP",
  ``LOOKUP_VAR name (write x v  env) y =
    if x = name then (v = y) else LOOKUP_VAR name env y``,
  `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ ASM_SIMP_TAC std_ss [LOOKUP_VAR_def,lookup_def, lookup_var_id_def,write_def,
       lookup_var_def] \\ SRW_TAC [] []);

val Eval_Val_INT = store_thm("Eval_Val_INT",
  ``!n. Eval env (Lit (IntLit n)) (INT n)``,
  SIMP_TAC (srw_ss()) [Once evaluate_cases,NUM_def,INT_def,Eval_def]);

val Eval_Val_NUM = store_thm("Eval_Val_NUM",
  ``!n. Eval env (Lit (IntLit (&n))) (NUM n)``,
  SIMP_TAC (srw_ss()) [Once evaluate_cases,NUM_def,INT_def,Eval_def]);

val Eval_Val_UNIT = store_thm("Eval_Val_UNIT",
  ``Eval env (Lit Unit) (UNIT_TYPE ())``,
  SIMP_TAC (srw_ss()) [Once evaluate_cases,UNIT_TYPE_def,Eval_def]);

val Eval_Val_BOOL = store_thm("Eval_Val_BOOL",
  ``!n. Eval env (Lit (Bool n)) (BOOL n)``,
  SIMP_TAC (srw_ss()) [Once evaluate_cases,BOOL_def,Eval_def]);

val Eval_Or = store_thm("Eval_Or",
  ``Eval env x1 (BOOL b1) ==>
    Eval env x2 (BOOL b2) ==>
    Eval env (Log Or x1 x2) (BOOL (b1 \/ b2))``,
  SIMP_TAC std_ss [Eval_def,NUM_def,BOOL_def] \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Q.EXISTS_TAC `(Litv (Bool b1))` \\ Cases_on `b1`
  \\ FULL_SIMP_TAC (srw_ss()) [do_log_def]
  \\ Q.EXISTS_TAC `0,empty_store` \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []);

val Eval_And = store_thm("Eval_And",
  ``Eval env x1 (BOOL b1) ==>
    Eval env x2 (BOOL b2) ==>
    Eval env (Log And x1 x2) (BOOL (b1 /\ b2))``,
  SIMP_TAC std_ss [Eval_def,NUM_def,BOOL_def] \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Q.EXISTS_TAC `(Litv (Bool b1))` \\ Cases_on `b1`
  \\ FULL_SIMP_TAC (srw_ss()) [do_log_def]
  \\ Q.EXISTS_TAC `0,empty_store` \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []);

val Eval_If = store_thm("Eval_If",
  ``(a1 ==> Eval env x1 (BOOL b1)) /\
    (a2 ==> Eval env x2 (a b2)) /\
    (a3 ==> Eval env x3 (a b3)) ==>
    (a1 /\ (CONTAINER b1 ==> a2) /\ (~CONTAINER b1 ==> a3) ==>
     Eval env (If x1 x2 x3) (a (if b1 then b2 else b3)))``,
  SIMP_TAC std_ss [Eval_def,NUM_def,BOOL_def] \\ SIMP_TAC std_ss [CONTAINER_def]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Cases_on `b1` \\ FULL_SIMP_TAC std_ss []
  THEN1 (Q.EXISTS_TAC `res` \\ ASM_SIMP_TAC std_ss []
    \\ Q.EXISTS_TAC `Litv (Bool T)` \\ ASM_SIMP_TAC (srw_ss()) [do_if_def]
    \\ Q.EXISTS_TAC `0,empty_store` \\ FULL_SIMP_TAC std_ss [])
  THEN1 (Q.EXISTS_TAC `res` \\ ASM_SIMP_TAC std_ss []
    \\ Q.EXISTS_TAC `Litv (Bool F)` \\ ASM_SIMP_TAC (srw_ss()) [do_if_def]
    \\ Q.EXISTS_TAC `0,empty_store` \\ FULL_SIMP_TAC std_ss []));

val Eval_Bool_Not = store_thm("Eval_Bool_Not",
  ``Eval env x1 (BOOL b1) ==>
    Eval env (App Equality x1 (Lit (Bool F))) (BOOL (~b1))``,
  SIMP_TAC std_ss [Eval_def,NUM_def,BOOL_def] \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC (srw_ss()) [do_app_cases]
  \\ Q.LIST_EXISTS_TAC [`(Litv (Bool b1))`, `Litv (Bool F)`, `env`, `Lit (Bool ~b1)`,
                        `0,empty_store`, `empty_store`]
  \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ SIMP_TAC (srw_ss ()) [do_eq_def]);

val Eval_Implies = store_thm("Eval_Implies",
  ``Eval env x1 (BOOL b1) ==>
    Eval env x2 (BOOL b2) ==>
    Eval env (If x1 x2 (Lit (Bool T))) (BOOL (b1 ==> b2))``,
  SIMP_TAC std_ss [Eval_def,NUM_def,BOOL_def] \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Q.EXISTS_TAC `(Litv (Bool b1))` \\ Cases_on `b1`
  \\ FULL_SIMP_TAC (srw_ss()) [do_if_def]
  \\ Q.EXISTS_TAC `0,empty_store` \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []);

val Eval_Var_SIMP = store_thm("Eval_Var_SIMP",
  ``Eval (write x v env) (Var (Short y)) p =
      if x = y then p v else Eval env (Var (Short y)) p``,
  `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ ASM_SIMP_TAC (srw_ss()) [LOOKUP_VAR_def,lookup_def, lookup_var_id_def,write_def,
       lookup_var_def,Eval_def,Once evaluate_cases,lookup_def, lookup_var_id_def]
  \\ SRW_TAC [] [] \\ SIMP_TAC (srw_ss()) [Eval_def,Once evaluate_cases,
       lookup_def, lookup_var_id_def]);

val Eval_Eq = store_thm("Eval_Eq",
  ``Eval env exp (a x) ==> Eval env exp ((Eq a x) x)``,
  SIMP_TAC std_ss [Eval_def,Eq_def]);

val FUN_FORALL = new_binder_definition("FUN_FORALL",
  ``($FUN_FORALL) = \(abs:'a->'b->v->bool) a v. !y. abs y a v``);

val FUN_EXISTS = new_binder_definition("FUN_EXISTS",
  ``($FUN_EXISTS) = \(abs:'a->'b->v->bool) a v. ?y. abs y a v``);

val Eval_FUN_FORALL = store_thm("Eval_FUN_FORALL",
  ``(!x. Eval env exp ((p x) f)) ==>
    Eval env exp ((FUN_FORALL x. p x) f)``,
  SIMP_TAC std_ss [Eval_def,Arrow_def,Eq_def] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [AppReturns_def,FUN_FORALL]
  \\ `?res. evaluate F env (0,empty_store) exp ((0,empty_store),Rval res)` by METIS_TAC []
  \\ Q.EXISTS_TAC `res` \\ FULL_SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ Q.PAT_ASSUM `!x.bbb` (STRIP_ASSUME_TAC o Q.SPEC `y`)
  \\ IMP_RES_TAC evaluate_11_Rval \\ FULL_SIMP_TAC (srw_ss()) []);

val Eval_FUN_FORALL_EQ = store_thm("Eval_FUN_FORALL_EQ",
  ``(!x. Eval env exp ((p x) f)) =
    Eval env exp ((FUN_FORALL x. p x) f)``,
  REPEAT STRIP_TAC \\ EQ_TAC \\ FULL_SIMP_TAC std_ss [Eval_FUN_FORALL]
  \\ EVAL_TAC \\ FULL_SIMP_TAC std_ss [FUN_FORALL] \\ METIS_TAC []);

val PULL_FORALL = save_thm("PULL_FORALL",
  METIS_PROVE [] ``((p ==> !x. q x) = (!x. p ==> q x)) /\
                   ((p /\ !x. q x) = (!x. p /\ q x))``)

val FUN_FORALL_PUSH1 = prove(
  ``(FUN_FORALL x. a --> (b x)) = (a --> FUN_FORALL x. b x)``,
  FULL_SIMP_TAC std_ss [Arrow_def,FUN_EQ_THM,AppReturns_def,FUN_FORALL,
    Eval_def,evaluate_closure_def] \\ REPEAT STRIP_TAC \\ REVERSE EQ_TAC
  THEN1 METIS_TAC [evaluate_11_Rval]
  \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [PULL_FORALL] \\ RES_TAC
  \\ POP_ASSUM (fn th => STRIP_ASSUME_TAC (Q.SPEC `env` th) THEN ASSUME_TAC th)
  \\ FULL_SIMP_TAC std_ss []
  \\ Q.EXISTS_TAC `u` \\ FULL_SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC
  \\ POP_ASSUM (MP_TAC o Q.SPEC `y`) \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss []
  \\ METIS_TAC [evaluate_11_Rval,PAIR_EQ]) |> GEN_ALL;

val FUN_FORALL_PUSH2 = prove(
  ``(FUN_FORALL x. (a x) --> b) = ((FUN_EXISTS x. a x) --> b)``,
  FULL_SIMP_TAC std_ss [Arrow_def,FUN_EQ_THM,AppReturns_def,FUN_FORALL,FUN_EXISTS,
    Eval_def] \\ METIS_TAC []) |> GEN_ALL;

val FUN_EXISTS_Eq = prove(
  ``(FUN_EXISTS x. Eq a x) = a``,
  SIMP_TAC std_ss [FUN_EQ_THM,FUN_EXISTS,Eq_def]) |> GEN_ALL;

val FUN_QUANT_SIMP = save_thm("FUN_QUANT_SIMP",
  LIST_CONJ [FUN_EXISTS_Eq,FUN_FORALL_PUSH1,FUN_FORALL_PUSH2]);

val write_rec_def = Define `
  write_rec funs (menv2,cenv2,env2) =
    (menv2,cenv2,build_rec_env funs (menv2,cenv2,env2) env2)`;

val FOLDR_LEMMA = prove(
  ``!funs. FOLDR (λ(f,x,e) env'. (f,rrr f)::env') env3 funs =
           MAP (λ(f,x,e). (f,rrr f)) funs ++ env3``,
  Induct \\ SRW_TAC [] [] \\ PairCases_on `h`
  \\ FULL_SIMP_TAC std_ss []);

val FOLDR_LEMMA2 = prove(
  ``!funs. FOLDR (λ(f,x,e) env'. write f (rrr f) env') (env1,env2,env3) funs =
           (env1,env2,MAP (λ(f,x,e). (f,rrr f)) funs ++ env3)``,
  Induct \\ SRW_TAC [] [] \\ PairCases_on `h`
  \\ FULL_SIMP_TAC std_ss [write_def]);

val write_rec_thm = store_thm("write_rec_thm",
  ``write_rec funs env =
    FOLDR (\(f,x,e) env'. write f (Recclosure env funs f) env') env funs``,
  PairCases_on `env`
  \\ SIMP_TAC std_ss [write_rec_def,build_rec_env_def,bind_def]
  \\ Q.SPEC_TAC (`Recclosure (env0,(env1,env2),env3) funs`,`rrr`)
  \\ SIMP_TAC std_ss [FOLDR_LEMMA,FOLDR_LEMMA2]);

val Eval_Recclosure_ALT = store_thm("Eval_Recclosure_ALT",
  ``!funs fname name body.
      (!v. a n v ==>
           Eval (write name v (write_rec funs env2)) body (b (f n))) ==>
      LOOKUP_VAR fname env (Recclosure env2 funs fname) ==>
      (find_recfun fname funs = SOME (name,body)) ==>
      Eval env (Var (Short fname)) ((Eq a n --> b) f)``,
  `?menv cenv eenv. env2 = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC std_ss [write_rec_def,write_def]
  \\ NTAC 6 STRIP_TAC \\ IMP_RES_TAC LOOKUP_VAR_THM
  \\ POP_ASSUM MP_TAC \\ POP_ASSUM (K ALL_TAC) \\ POP_ASSUM MP_TAC
  \\ FULL_SIMP_TAC std_ss [Eval_def,Arrow_def] \\ REPEAT STRIP_TAC
  \\ POP_ASSUM MP_TAC \\ POP_ASSUM MP_TAC \\ ONCE_REWRITE_TAC [evaluate_cases]
  \\ FULL_SIMP_TAC (srw_ss()) [AppReturns_def,Eq_def,
       do_app_def,evaluate_closure_def]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC (srw_ss()) [bind_def,build_rec_env_def,FOLDR]);

val Eval_Recclosure = store_thm("Eval_Recclosure",
  ``(!v. a n v ==>
         Eval (write name v (write_rec [(fname,name,body)] env2))
              body (b (f n))) ==>
    LOOKUP_VAR fname env (Recclosure env2 [(fname,name,body)] fname) ==>
    Eval env (Var (Short fname)) ((Eq a n --> b) f)``,
  (Eval_Recclosure_ALT |> Q.SPECL [`[(fname,name,body)]`,`fname`]
    |> SIMP_RULE (srw_ss()) [Once find_recfun_def] |> ASSUME_TAC)
  \\ FULL_SIMP_TAC std_ss []);

val SafeVar_def = Define `SafeVar = Var`;

val Eval_Eq_Recclosure = store_thm("Eval_Eq_Recclosure",
  ``LOOKUP_VAR name env (Recclosure x1 x2 x3) ==>
    (P f (Recclosure x1 x2 x3) =
     Eval env (Var (Short name)) (P f))``,
  `?menv cenv eenv. env = (menv,cenv,eenv)` by METIS_TAC [PAIR]
  \\ ASM_SIMP_TAC std_ss [Eval_Var_SIMP,Eval_def,LOOKUP_VAR_def,lookup_var_def]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases]
  \\ REPEAT STRIP_TAC \\ EQ_TAC \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [lookup_var_id_def, LOOKUP_VAR_def]
  \\ FULL_SIMP_TAC (srw_ss()) []
  \\ METIS_TAC []);

val Eval_Eq_Fun = store_thm("Eval_Eq_Fun",
  ``Eval env (Fun v x) p ==>
    !env2. Eval env2 (Var name) ($= (Closure env v x)) ==>
           Eval env2 (Var name) p``,
  SIMP_TAC std_ss [Eval_Var_SIMP,Eval_def]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_cases]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC []);

val Eval_WEAKEN = store_thm("Eval_WEAKEN",
  ``Eval env exp P ==> (!v. P v ==> Q v) ==> Eval env exp Q``,
  SIMP_TAC std_ss [Eval_def] \\ METIS_TAC []);

val Eval_CONST = store_thm("Eval_CONST",
  ``(!v. P v = (v = x)) ==>
    Eval env (Var name) ($= x) ==> Eval env (Var name) P``,
  SIMP_TAC std_ss [Eval_def])


(* arithmetic for integers *)

val Eval_Opn = prove(
  ``!f n1 n2.
        Eval env x1 (INT n1) ==>
        Eval env x2 (INT n2) ==>
        PRECONDITION (((f = Divide) \/ (f = Modulo)) ==> ~(n2 = 0)) ==>
        Eval env (App (Opn f) x1 x2) (INT (opn_lookup f n1 n2))``,
  SIMP_TAC std_ss [Eval_def,INT_def] \\ SIMP_TAC std_ss [PRECONDITION_def]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Q.LIST_EXISTS_TAC [`Litv (IntLit n1)`,`Litv (IntLit n2)`]
  \\ FULL_SIMP_TAC (srw_ss()) [do_app_def]
  \\ Cases_on `f` \\ FULL_SIMP_TAC (srw_ss()) []
  \\ REPEAT (Q.EXISTS_TAC `0,empty_store`) \\ FULL_SIMP_TAC std_ss []
  \\ Q.EXISTS_TAC `empty_store`
  \\ Q.EXISTS_TAC `0`
  \\ SRW_TAC [] []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []);

local
  fun f name q =
    save_thm("Eval_" ^ name,SIMP_RULE (srw_ss()) [opn_lookup_def,EVAL ``PRECONDITION T``]
                              (Q.SPEC q Eval_Opn))
in
  val Eval_INT_ADD  = f "INT_ADD" `Plus`
  val Eval_INT_SUB  = f "INT_SUB" `Minus`
  val Eval_INT_MULT = f "INT_MULT" `Times`
  val Eval_INT_DIV  = f "INT_DIV" `Divide`
  val Eval_INT_MOD  = f "INT_MOD" `Modulo`
end

val Eval_Opb = prove(
  ``!f n1 n2.
        Eval env x1 (INT n1) ==>
        Eval env x2 (INT n2) ==>
        Eval env (App (Opb f) x1 x2) (BOOL (opb_lookup f n1 n2))``,
  SIMP_TAC std_ss [Eval_def,INT_def,BOOL_def] \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Q.LIST_EXISTS_TAC [`Litv (IntLit n1)`,`Litv (IntLit n2)`]
  \\ FULL_SIMP_TAC (srw_ss()) [do_app_def]
  \\ Q.LIST_EXISTS_TAC [`0,empty_store`, `empty_store`, `0`] \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []);

local
  fun f name q = let
    val th = SIMP_RULE (srw_ss()) [opb_lookup_def] (Q.SPEC q Eval_Opb)
    val _ = save_thm("Eval_" ^ name,SPEC_ALL th)
   in th end
in
  val Eval_INT_LESS = f "INT_LESS" `Lt`
  val Eval_INT_LESS_EQ = f "INT_LESS_EQ" `Leq`
  val Eval_INT_GREATER = f "INT_GREATER" `Gt`
  val Eval_INT_GREATER_EQ = f "INT_GREATER_EQ" `Geq`
end

local

val th0 = Q.SPEC `0` Eval_Val_INT
val th_sub = MATCH_MP (MATCH_MP Eval_INT_SUB (Q.SPEC `0` Eval_Val_INT))
            (ASSUME ``Eval env (Var (Short "k")) (INT k)``)
val th1 = ASSUME ``Eval env (Var (Short "k")) (INT k)``
val th2 = Eval_INT_LESS  |> Q.SPECL [`k`,`0`]
          |> (fn th => MATCH_MP th th1) |> (fn th => MATCH_MP th th0)
val th = MATCH_MP Eval_If (LIST_CONJ (map (DISCH T) [th2,th_sub,th1]))
         |> REWRITE_RULE [CONTAINER_def]
val code =
  ``Let (SOME "k") x1
       (If (App (Opb Lt) (Var (Short "k")) (Lit (IntLit 0)))
          (App (Opn Minus) (Lit (IntLit 0)) (Var (Short "k")))
          (Var (Short "k")))``

in

val Eval_Num_ABS = store_thm("Eval_Num_ABS",
  ``Eval env x1 (INT i) ==>
    Eval env ^code (NUM (Num (ABS i)))``,
  SIMP_TAC std_ss [NUM_def]
  \\ `&(Num (ABS i)) = let k = i in if k < 0 then 0 - k else k` by
    (FULL_SIMP_TAC std_ss [LET_DEF] THEN intLib.COOPER_TAC)
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ PairCases_on `env` \\ MATCH_MP_TAC (GEN_ALL Eval_Let)
  \\ Q.EXISTS_TAC `INT` \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ MATCH_MP_TAC (GEN_ALL (DISCH_ALL th))
  \\ FULL_SIMP_TAC std_ss [Eval_Var_SIMP]);

end;

val Eval_int_of_num = store_thm("Eval_int_of_num",
  ``Eval env x1 (NUM n) ==>
    Eval env x1 (INT (int_of_num n))``,
  SIMP_TAC std_ss [NUM_def]);

val Eval_int_of_num_o = store_thm("Eval_int_of_num_o",
  ``Eval env x1 ((A --> NUM) f) ==>
    Eval env x1 ((A --> INT) (int_of_num o f))``,
  SIMP_TAC std_ss [NUM_def,Arrow_def]);

val Eval_o_int_of_num = store_thm("Eval_o_int_of_num",
  ``Eval env x1 ((INT --> A) f) ==>
    Eval env x1 ((NUM --> A) (f o int_of_num))``,
  SIMP_TAC std_ss [NUM_def,Arrow_def,Eval_def]
  \\ METIS_TAC[]);

(* arithmetic for num *)

val Eval_NUM_ADD = save_thm("Eval_NUM_ADD",
  Eval_INT_ADD |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_ADD]);

val Eval_NUM_MULT = save_thm("Eval_NUM_MULT",
  Eval_INT_MULT |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_MUL]);

val Eval_NUM_DIV = save_thm("Eval_NUM_DIV",
  Eval_INT_DIV |> Q.SPECL [`&n1`,`&n2`]
  |> UNDISCH_ALL |> DISCH ``PRECONDITION (&n2 <> 0)``
  |> SIMP_RULE std_ss [GSYM NUM_def,INT_DIV,PRECONDITION_def,INT_INJ]
  |> CONV_RULE ((RATOR_CONV o RAND_CONV) (ONCE_REWRITE_CONV [GSYM PRECONDITION_def]))
  |> DISCH ``Eval env x2 (INT (&n2))``
  |> DISCH ``Eval env x1 (INT (&n1))``
  |> SIMP_RULE std_ss [GSYM NUM_def,INT_DIV]);

val Eval_NUM_MOD = save_thm("Eval_NUM_MOD",
  Eval_INT_MOD |> Q.SPECL [`&n1`,`&n2`]
  |> UNDISCH_ALL |> DISCH ``PRECONDITION (&n2 <> 0)``
  |> SIMP_RULE std_ss [GSYM NUM_def,INT_MOD,PRECONDITION_def,INT_INJ]
  |> CONV_RULE ((RATOR_CONV o RAND_CONV) (ONCE_REWRITE_CONV [GSYM PRECONDITION_def]))
  |> DISCH ``Eval env x2 (INT (&n2))``
  |> DISCH ``Eval env x1 (INT (&n1))``
  |> SIMP_RULE std_ss [GSYM NUM_def,INT_MOD]);

val Eval_NUM_MULT =
  Eval_INT_MULT |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_MUL]

local

val th0 = Q.SPEC `0` Eval_Val_INT
val th1 = ASSUME ``Eval env (Var (Short "k")) (INT k)``
val th2 = Eval_INT_LESS  |> Q.SPECL [`k`,`0`]
          |> (fn th => MATCH_MP th th1) |> (fn th => MATCH_MP th th0)
val th = MATCH_MP Eval_If (LIST_CONJ (map (DISCH T) [th2,th0,th1]))
         |> REWRITE_RULE [CONTAINER_def]
val code =
  ``Let (SOME "k") (App (Opn Minus) x1 x2)
      (If (App (Opb Lt) (Var (Short "k")) (Lit (IntLit 0)))
          (Lit (IntLit 0)) (Var (Short "k"))): exp``

in

val Eval_NUM_SUB = store_thm("Eval_NUM_SUB",
  ``Eval env x1 (NUM m) ==>
    Eval env x2 (NUM n) ==>
    Eval env ^code (NUM (m - n))``,
  SIMP_TAC std_ss [NUM_def]
  \\ `&(m - n:num) = let k = &m - &n in if k < 0 then 0 else k:int` by
   (FULL_SIMP_TAC std_ss [LET_DEF,INT_LT_SUB_RADD,INT_ADD,INT_LT]
    \\ Cases_on `m<n` \\ FULL_SIMP_TAC std_ss []
    THEN1 (`m - n = 0` by DECIDE_TAC \\ ASM_REWRITE_TAC [])
    \\ FULL_SIMP_TAC std_ss [NOT_LESS,INT_SUB])
  \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC \\ PairCases_on `env` \\ MATCH_MP_TAC (GEN_ALL Eval_Let)
  \\ Q.EXISTS_TAC `INT` \\ FULL_SIMP_TAC std_ss [] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [Eval_INT_SUB]
  \\ MATCH_MP_TAC (GEN_ALL (DISCH_ALL th))
  \\ FULL_SIMP_TAC std_ss [Eval_Var_SIMP]);

end;

val Eval_NUM_LESS = save_thm("Eval_NUM_LESS",
  Eval_INT_LESS |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_LT,INT_LE,int_ge,int_gt]);

val Eval_NUM_LESS_EQ = save_thm("Eval_NUM_LESS_EQ",
  Eval_INT_LESS_EQ |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_LT,INT_LE,int_ge,int_gt]);

val Eval_NUM_GREATER = save_thm("Eval_NUM_GREATER",
  Eval_INT_GREATER |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_LT,INT_LE,int_ge,int_gt]
  |> REWRITE_RULE [GSYM GREATER_DEF, GSYM GREATER_EQ]);

val Eval_NUM_GREATER_EQ = save_thm("Eval_NUM_GREATER_EQ",
  Eval_INT_GREATER_EQ |> Q.SPECL [`&n1`,`&n2`]
  |> REWRITE_RULE [GSYM NUM_def,INT_LT,INT_LE,int_ge,int_gt]
  |> REWRITE_RULE [GSYM GREATER_DEF, GSYM GREATER_EQ]);

val Eval_NUM_EQ_0 = store_thm("Eval_NUM_EQ_0",
  ``!n. Eval env x (NUM n) ==>
        Eval env (App (Opb Leq) x (Lit (IntLit 0))) (BOOL (n = 0))``,
  REPEAT STRIP_TAC \\ ASSUME_TAC (Q.SPEC `0` Eval_Val_NUM)
  \\ FULL_SIMP_TAC std_ss [NUM_def]
  \\ `(n = 0) = (&n <= 0)` by intLib.COOPER_TAC
  \\ FULL_SIMP_TAC std_ss [Eval_INT_LESS_EQ]);


(* Equality *)

val no_closures_def = tDefine "no_closures" `
  (no_closures (Litv l) = T) /\
  (no_closures (Conv name vs) = EVERY no_closures vs) /\
  (no_closures _ = F)`
 (WF_REL_TAC `measure v_size` \\ REPEAT STRIP_TAC
  \\ Induct_on `vs` \\ FULL_SIMP_TAC (srw_ss()) [MEM]
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC (srw_ss()) [MEM,v_size_def]
  \\ DECIDE_TAC)

val types_match_def = tDefine "types_match" `
  (types_match (Litv l1) (Litv l2) = T) /\
  (types_match (Loc l1) (Loc l2) = T) /\
  (types_match (Conv cn1 vs1) (Conv cn2 vs2) =
    ((cn1 <> cn2) \/ types_match_list vs1 vs2)) /\
  (types_match _ _ = F) /\
  (types_match_list [] [] = T) /\
  (types_match_list (v1::vs1) (v2::vs2) =
    (types_match v1 v2 /\ types_match_list vs1 vs2)) /\
(* We could change this case to T, or change the semantics to have a type error
 * when equality reaches unequal-length lists *)
  (types_match_list _ _ = F)` (
    WF_REL_TAC `measure (\x. case x of INL (v1,v2) => v_size v1 |
                                       INR (vs1,vs2) => v7_size vs1)`);

val EqualityType_def = Define `
  EqualityType (abs:'a->v->bool) <=>
    (!x1 v1. abs x1 v1 ==> no_closures v1) /\
    (!x1 v1 x2 v2. abs x1 v1 /\ abs x2 v2 ==> ((v1 = v2) = (x1 = x2))) /\
    (!x1 v1 x2 v2. abs x1 v1 /\ abs x2 v2 ==> types_match v1 v2)`;

val EqualityType_NUM_BOOL = store_thm("EqualityType_NUM_BOOL",
  ``EqualityType NUM /\ EqualityType INT /\
    EqualityType BOOL /\ EqualityType UNIT_TYPE``,
  EVAL_TAC \\ FULL_SIMP_TAC (srw_ss()) [no_closures_def, types_match_def]);

val no_closures_IMP_NOT_contains_closure = store_thm(
   "no_closures_IMP_NOT_contains_closure",
  ``!res. no_closures res ==> ~contains_closure res``,
  HO_MATCH_MP_TAC contains_closure_ind
  \\ SIMP_TAC std_ss [no_closures_def,EVERY_MEM,contains_closure_def,
       EXISTS_MEM] \\ REPEAT STRIP_TAC
  \\ SIMP_TAC std_ss [METIS_PROVE [] ``~b \/ c <=> (b ==> c)``]
  \\ REPEAT STRIP_TAC \\ RES_TAC);

val types_match_list_length = prove(
  ``!vs1 vs2. types_match_list vs1 vs2 ==> LENGTH vs1 = LENGTH vs2``,
  Induct \\ Cases_on`vs2` \\ rw[types_match_def])

val type_match_implies_do_eq_succeeds = prove(``
  (!v1 v2. types_match v1 v2 ==> (do_eq v1 v2 = Eq_val (v1 = v2))) /\
  (!vs1 vs2.
    types_match_list vs1 vs2 ==> (do_eq_list vs1 vs2 = Eq_val (vs1 = vs2)))``,
  ho_match_mp_tac do_eq_ind
  \\ rw [do_eq_def, types_match_def]
  \\ imp_res_tac types_match_list_length
  \\ fs[]);

val do_eq_succeeds = prove(``
  (!a x1 v1 x2 v2. EqualityType a /\ a x1 v1 /\ a x2 v2 ==>
                   (do_eq v1 v2 = Eq_val (x1 = x2)))``,
 rw [EqualityType_def]
 \\ res_tac
 \\ imp_res_tac type_match_implies_do_eq_succeeds
 \\ Cases_on `v1 = v2`
 \\ fs []);

val Eval_Equality = store_thm("Eval_Equality",
  ``Eval env x1 (a y1) /\ Eval env x2 (a y2) ==>
    EqualityType a ==>
    Eval env (App Equality x1 x2) (BOOL (y1 = y2))``,
  SIMP_TAC std_ss [Eval_def,BOOL_def] \\ SIMP_TAC std_ss []
  \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ SIMP_TAC (srw_ss()) []
  \\ Q.LIST_EXISTS_TAC [`res`,`res'`]
  \\ FULL_SIMP_TAC (srw_ss()) [do_app_cases]
  \\ Q.LIST_EXISTS_TAC [`env`, `Lit (Bool (res = res'))`]
  \\ Q.LIST_EXISTS_TAC [`0,empty_store`, `empty_store`, `0`]
  \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [evaluate_cases]
  \\ FULL_SIMP_TAC (srw_ss()) []
  \\ IMP_RES_TAC do_eq_succeeds
  \\ FULL_SIMP_TAC (srw_ss()) [EqualityType_def]);

(* evaluation of declarations *)

val Decls_def = Define `
  Decls mn env s1 ds env2 s2 =
    ?menv1 cenv1 env1 new_tds res_env.
      (env = (menv1,cenv1,env1)) /\
      evaluate_decs F mn env s1 ds (s2,new_tds, Rval res_env) /\
      (env2 = (menv1,merge_envC (emp,new_tds) cenv1,merge res_env env1))`;

val DeclAssum_def = Define `
  DeclAssum ds env tys =
    Decls NONE ([],init_envC,init_env) ((0,[]),{}) ds env ((0,[]),tys)`;

val write_tds_def = Define `
  write_tds mn tds ((menv1,cenv1,env1):all_env) =
    (menv1,merge_envC ([],build_tdefs mn tds) cenv1,env1):all_env`;

val Decls_Dtype = store_thm("Decls_Dtype",
  ``!mn env s tds env2 s2.
      Decls mn env s [Dtype tds] env2 s2 <=>
      check_dup_ctors tds /\
      DISJOINT (type_defs_to_new_tdecs mn tds) (SND s) /\
      (s2 = (FST s,type_defs_to_new_tdecs mn tds UNION SND s)) /\
      (env2 = write_tds mn tds env)``,
  SIMP_TAC std_ss [Decls_def]
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases] \\ SIMP_TAC (srw_ss()) []
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases] \\ SIMP_TAC (srw_ss()) []
  \\ SIMP_TAC (srw_ss()) [evaluate_dec_cases, combine_dec_result_def,
                          merge_def, emp_def, all_env_to_cenv_def]
  \\ Cases_on `s` \\ SIMP_TAC std_ss [PULL_EXISTS,write_tds_def]
  \\ REPEAT STRIP_TAC \\ PairCases_on `env`
  \\ FULL_SIMP_TAC std_ss [write_tds_def,AC CONJ_COMM CONJ_ASSOC,APPEND]);

val Decls_Dlet = store_thm("Decls_Dlet",
  ``!mn env s1 v e s2 env2.
      Decls mn env s1 [Dlet (Pvar v) e] env2 s2 <=>
      ?x. (SND s2 = SND s1) /\
          evaluate F env (FST s1) e ((FST s2),Rval x) /\
          (env2 = write v x env)``,
  SIMP_TAC std_ss [Decls_def]
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases] \\ SIMP_TAC (srw_ss()) []
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases] \\ SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC (srw_ss()) [pat_bindings_def,ALL_DISTINCT,MEM,
       pmatch_def,bind_def, evaluate_dec_cases,
       combine_dec_result_def, emp_def, merge_def]
  \\ FULL_SIMP_TAC std_ss [PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ PairCases_on `env` \\ Cases_on `s1` \\ Cases_on `s2`
  \\ FULL_SIMP_TAC std_ss [write_def,merge_envC_def,merge_def,APPEND,emp_def]
  \\ METIS_TAC [big_unclocked, pair_CASES]);

val FOLDR_LEMMA = prove(
  ``!xs ys. FOLDR (\(x1,x2,x3) x4. bind x1 (f x1 x2 x3) x4) [] xs ++ ys =
            FOLDR (\(x1,x2,x3) x4. bind x1 (f x1 x2 x3) x4) ys xs``,
  Induct \\ FULL_SIMP_TAC (srw_ss()) [bind_def,FORALL_PROD]);

val Decls_Dletrec = store_thm("Decls_Dletrec",
  ``!mn env s1 funs s2 env2.
      Decls mn env s1 [Dletrec funs] env2 s2 <=>
      (s2 = s1) /\
      ALL_DISTINCT (MAP (\(x,y,z). x) funs) /\
      (env2 = write_rec funs env)``,
  SIMP_TAC std_ss [Decls_def]
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases] \\ SIMP_TAC (srw_ss()) []
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases] \\ SIMP_TAC (srw_ss()) []
  \\ FULL_SIMP_TAC (srw_ss()) [pat_bindings_def,ALL_DISTINCT,MEM,
       pmatch_def,bind_def,merge_def, emp_def, evaluate_dec_cases,
       combine_dec_result_def,PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ PairCases_on `env` \\ Cases_on `s1` \\ Cases_on `s2`
  \\ FULL_SIMP_TAC std_ss [write_def,merge_envC_def,
       merge_def,APPEND,emp_def,write_rec_def,APPEND,
       build_rec_env_def,FOLDR_LEMMA]
  \\ METIS_TAC []);

val _ = temp_overload_on("has_emp",``\x. SND (FST x) = empty_store``)

val LUPDATE_NIL = prove(
  ``!xs n x. (LUPDATE x n xs = []) = (xs = [])``,
  Cases \\ Cases_on `n` \\ FULL_SIMP_TAC (srw_ss()) [LUPDATE_def]);

val evaluate_empty_store_lemma = prove(
 ``(!ck env s e r1.
      evaluate ck env s e r1 ==> has_emp r1 ==> (SND s = empty_store)) /\
   (!ck env s es r1.
      evaluate_list ck env s es r1 ==> has_emp r1 ==> (SND s = empty_store)) /\
   (!ck env s v pes errv r1.
      evaluate_match ck env s v pes errv r1 ==> has_emp r1 ==> (SND s = empty_store))``,
  HO_MATCH_MP_TAC evaluate_ind \\ rw [] \\ POP_ASSUM MP_TAC
  \\ TRY (Cases_on `uop`)
  \\ FULL_SIMP_TAC (srw_ss()) [do_uapp_def,do_app_cases,LET_DEF,store_alloc_def]
  THEN1 (Cases_on `s2`
    \\ FULL_SIMP_TAC (srw_ss()) [store_alloc_def,empty_store_def,APPEND])
  THEN1 (Cases_on `v` \\ FULL_SIMP_TAC (srw_ss()) []
    \\ Cases_on `store_lookup n s2` \\ FULL_SIMP_TAC (srw_ss()) [])
  \\ FULL_SIMP_TAC std_ss [IMP_DISJ_THM]
  \\ SRW_TAC [] []
  \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [store_assign_def,empty_store_def,LUPDATE_NIL])
  |> SIMP_RULE std_ss [PULL_EXISTS,AND_IMP_INTRO];

val _ = temp_overload_on("has_emp_no_fail",
  ``\x. (SND (FST x) = empty_store:'a store) /\
        ~(SND x = (Rerr Rtype_error):('b,'c) result)``)

val sind = IndDefLib.derive_strong_induction(evaluate_rules,evaluate_ind);

val do_app_empty_store = prove(
  ``!op v1 v2.
      s3 <> empty_store ==>
      ~(do_app env s3 op v1 v2 = SOME (env',empty_store,e''))``,
  Cases \\ SIMP_TAC std_ss [do_app_def] \\ SRW_TAC [] []
  \\ BasicProvers.EVERY_CASE_TAC \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [store_assign_def]
  \\ POP_ASSUM (ASSUME_TAC o GSYM)
  \\ FULL_SIMP_TAC std_ss [LENGTH_LUPDATE,empty_store_def,GSYM LENGTH_NIL]);

val do_app_lemma = prove(
  ``!op.
      (do_app env empty_store op v1 v2 = SOME (env',empty_store,e'')) ==>
      !t. do_app env t op v1 v2 = SOME (env',t,e'')``,
  Cases \\ FULL_SIMP_TAC (srw_ss()) [do_app_def] \\ REPEAT STRIP_TAC
  \\ BasicProvers.EVERY_CASE_TAC \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC (srw_ss()) [store_assign_def]
  \\ POP_ASSUM MP_TAC \\ FULL_SIMP_TAC std_ss []
  \\ TRY (Cases_on `l` \\ FULL_SIMP_TAC (srw_ss()) [])
  \\ FULL_SIMP_TAC (srw_ss()) [empty_store_def]);

val pmatch_lemma = prove(
  ``(!cenv (s:v store) (p:pat) v env x.
      (pmatch cenv empty_store p v env = x) /\ x <> Match_type_error ==>
      !s. (pmatch cenv s p v env = x)) /\
    (!cenv (s:v store) (p:pat list) vs env x.
      (pmatch_list cenv empty_store p vs env = x) /\ x <> Match_type_error ==>
      !s. (pmatch_list cenv s p vs env = x))``,
  HO_MATCH_MP_TAC pmatch_ind \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [pmatch_def]
  \\ FULL_SIMP_TAC std_ss [store_lookup_def,empty_store_def,LENGTH]
  THEN1 (BasicProvers.EVERY_CASE_TAC \\ rw [])
  THEN1 (METIS_TAC [])
  \\ Cases_on `pmatch cenv [] p v env`
  \\ FULL_SIMP_TAC (srw_ss()) []
  \\ Q.PAT_ASSUM `No_match = x` (ASSUME_TAC o GSYM)
  \\ FULL_SIMP_TAC (srw_ss()) []);

val evaluate_empty_store_IMP_any_store = prove(
 ``(!ck env s e r1.
      evaluate ck env s e r1 ==> (ck = F) /\ has_emp_no_fail r1 ==>
      !t. evaluate ck env t e (t,SND r1)) /\
   (!ck env s es r1.
      evaluate_list ck env s es r1 ==> (ck = F) /\ has_emp_no_fail r1 ==>
      !t. evaluate_list ck env t es (t,SND r1)) /\
   (!ck env s v pes errv r1.
      evaluate_match ck env s v pes errv r1 ==> (ck = F) /\ has_emp_no_fail r1 ==>
      !t. evaluate_match ck env t v pes errv (t,SND r1))``,
  HO_MATCH_MP_TAC sind \\ FULL_SIMP_TAC (srw_ss()) [] \\ REPEAT STRIP_TAC
  \\ ONCE_REWRITE_TAC [evaluate_cases] \\ FULL_SIMP_TAC (srw_ss()) []
  THEN1
   (Cases_on `r1`
    \\ `SND s' = empty_store` by IMP_RES_TAC evaluate_empty_store_lemma
    \\ FULL_SIMP_TAC std_ss []
    \\ Cases_on `r` \\ FULL_SIMP_TAC (srw_ss()) [] \\ METIS_TAC [])
  THEN1
   METIS_TAC []
  THEN1
   (Q.LIST_EXISTS_TAC [`v`,`s2`] \\ FULL_SIMP_TAC std_ss []
    \\ `s2 = empty_store` by ALL_TAC THEN1
     (Cases_on `uop`
      \\ FULL_SIMP_TAC (srw_ss()) [do_uapp_def,LET_DEF,store_alloc_def]
      \\ FULL_SIMP_TAC (srw_ss()) [GSYM SNOC_APPEND,empty_store_def]
      \\ Cases_on `v`
      \\ FULL_SIMP_TAC (srw_ss()) [GSYM SNOC_APPEND,empty_store_def]
      \\ Cases_on `store_lookup n s2` \\ FULL_SIMP_TAC (srw_ss()) [])
    \\ FULL_SIMP_TAC std_ss []
    \\ Cases_on `uop`
    \\ FULL_SIMP_TAC (srw_ss()) [do_uapp_def,LET_DEF,store_alloc_def]
    \\ Cases_on `v`
    \\ FULL_SIMP_TAC (srw_ss()) [do_uapp_def,LET_DEF,
         store_lookup_def,empty_store_def])
  THEN1
   (`s4 = empty_store` by (IMP_RES_TAC evaluate_empty_store_lemma \\ FULL_SIMP_TAC std_ss [])
    \\ `s3 = empty_store` by METIS_TAC [do_app_empty_store]
    \\ FULL_SIMP_TAC std_ss []
    \\ `SND s' = empty_store` by (IMP_RES_TAC evaluate_empty_store_lemma \\ FULL_SIMP_TAC std_ss [])
    \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC do_app_lemma
    \\ Cases_on `r1` \\ Cases_on `r` \\ FULL_SIMP_TAC (srw_ss()) []
    \\ METIS_TAC [pair_CASES, FST, SND])
  \\ TRY (`SND s' = empty_store` by IMP_RES_TAC evaluate_empty_store_lemma
          \\ FULL_SIMP_TAC std_ss [] \\ METIS_TAC [])
  THEN1
   (`s = empty_store` by IMP_RES_TAC evaluate_empty_store_lemma
    \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC pmatch_lemma
    \\ PairCases_on `t`
    \\ FULL_SIMP_TAC (srw_ss()) [])
  THEN1
   (`s = empty_store` by IMP_RES_TAC evaluate_empty_store_lemma
    \\ FULL_SIMP_TAC std_ss [] \\ IMP_RES_TAC pmatch_lemma
    \\ PairCases_on `t`
    \\ FULL_SIMP_TAC (srw_ss()) []));

val evaluate_empty_store_IMP = store_thm("evaluate_empty_store_IMP",
  ``evaluate F env (c,empty_store) x ((c',empty_store),Rval y) ==>
    !s. evaluate F env s x (s,Rval y)``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC evaluate_empty_store_IMP_any_store
  \\ FULL_SIMP_TAC (srw_ss()) []);

val evaluate_empty_store_EQ = store_thm("evaluate_empty_store_EQ",
  ``evaluate F env (c,empty_store) x ((c,empty_store),Rval y) =
    !s. evaluate F env s x (s,Rval y)``,
  METIS_TAC [evaluate_empty_store_IMP]);

val do_app_empty_store = store_thm("do_app_empty_store",
  ``(do_app env s3 Opapp v1 v2 = SOME (env',empty_store,e3)) <=>
    (do_app env s3 Opapp v1 v2 = SOME (env',empty_store,e3)) /\ (s3 = empty_store)``,
  SIMP_TAC (srw_ss()) [do_app_def] \\ Cases_on `v1`
  \\ SIMP_TAC (srw_ss()) [do_app_def] \\ REPEAT BasicProvers.FULL_CASE_TAC
  \\ METIS_TAC []);

val evaluate_empty_store = store_thm("evaluate_empty_store",
  ``evaluate F env (c,s2) xs (((c',empty_store),Rval ys)) <=>
    evaluate F env (c,s2) xs (((c',empty_store),Rval ys)) /\ (s2 = empty_store)``,
  REPEAT STRIP_TAC \\ EQ_TAC \\ REPEAT STRIP_TAC
  \\ IMP_RES_TAC evaluate_empty_store_lemma \\ FULL_SIMP_TAC std_ss []);

val evaluate_list_empty_store = prove(
  ``evaluate_list F env (c,s2) xs ((c',empty_store),Rval ys) ==> (s2 = empty_store)``,
  REPEAT STRIP_TAC \\ IMP_RES_TAC evaluate_empty_store_lemma
  \\ FULL_SIMP_TAC (srw_ss()) []);

val combine_dec_result_rval = Q.prove (
  `!new_env cenv env.
     combine_dec_result new_env (Rval env) =
     Rval (merge env new_env)`,
  rw [combine_dec_result_def]);

val combine_dec_result_rerr = Q.prove (
  `!new_env err.
     combine_dec_result new_env (Rerr err) = Rerr err`,
  rw [combine_dec_result_def]);

val merge_envC_empty = Q.prove (
  `!cenv. merge_envC ([],[]) cenv = cenv`,
  rw [] \\ PairCases_on `cenv`
  \\ rw [merge_envC_def, merge_def]);

val merge_env_def = Define `
  merge_env (env1:all_env) (env2:all_env) = (env1:all_env)`;

val Decls_NIL = store_thm("Decls_APPEND",
  ``!s1 s3 mn env1 ds1 ds2 env3.
      Decls mn env1 s1 [] env3 s3 <=> (env3 = env1) /\ (s3 = s1)``,
  REPEAT STRIP_TAC \\ PairCases_on `env1`
  \\ FULL_SIMP_TAC std_ss [APPEND,Decls_def,PULL_EXISTS]
  \\ SIMP_TAC std_ss [Once evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [merge_def,emp_def,merge_envC_def]
  \\ METIS_TAC []);

val Decls_CONS = store_thm("Decls_CONS",
  ``!s1 s3 mn env1 ds1 ds2 env3.
      Decls mn env1 s1 (d::ds2) env3 s3 =
      ?env2 s2.
         Decls mn env1 s1 [d] env2 s2 /\
         Decls mn env2 s2 ds2 env3 s3``,
  FULL_SIMP_TAC std_ss [APPEND,Decls_def,PULL_EXISTS]
  \\ REPEAT STRIP_TAC
  \\ `?menv1 cenv1 eenv1. env1 = (menv1,cenv1,eenv1)` by METIS_TAC [PAIR]
  \\ FULL_SIMP_TAC std_ss []
  \\ SIMP_TAC (srw_ss()) [Once evaluate_decs_cases]
  \\ FULL_SIMP_TAC std_ss []
  \\ ONCE_REWRITE_TAC [EQ_SYM_EQ]
  \\ SIMP_TAC (srw_ss()) [Once evaluate_decs_cases]
  \\ FULL_SIMP_TAC std_ss [PULL_EXISTS]
  \\ REPEAT STRIP_TAC \\ EQ_TAC \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [``evaluate_decs F a0 a1 a2 [] a4``
        |> SIMP_CONV (srw_ss()) [Once evaluate_decs_cases]]
  \\ Cases_on `cenv1`
  \\ FULL_SIMP_TAC std_ss [merge_envC_def,emp_def,APPEND,merge_def]
  THEN1 (POP_ASSUM MP_TAC
    \\ NTAC 3 (Q.PAT_ASSUM `yyy = xxx` (fn th => FULL_SIMP_TAC std_ss [th]))
    \\ Q.PAT_ASSUM `yyy = xxx` MP_TAC
    \\ SIMP_TAC (srw_ss()) [Once combine_dec_result_def,merge_def,APPEND]
    \\ REPEAT STRIP_TAC \\ FULL_SIMP_TAC std_ss [APPEND]
    \\ Q.LIST_EXISTS_TAC [`s2'`,`new_tds'`,`new_tds'''`,`new_env`,`Rval res_env'`]
    \\ FULL_SIMP_TAC std_ss []
    \\ FULL_SIMP_TAC (srw_ss()) [combine_dec_result_def,merge_def])
  THEN1 (SIMP_TAC (srw_ss()) [combine_dec_result_def]
    \\ Cases_on `r` \\ FULL_SIMP_TAC (srw_ss()) [combine_dec_result_def]
    \\ FULL_SIMP_TAC std_ss [merge_def,APPEND]
    \\ METIS_TAC []));

val Decls_APPEND = store_thm("Decls_APPEND",
  ``!s1 s3 mn env1 ds1 ds2 env3.
      Decls mn env1 s1 (ds1 ++ ds2) env3 s3 =
      ?env2 s2.
         Decls mn env1 s1 ds1 env2 s2 /\
         Decls mn env2 s2 ds2 env3 s3``,
  Induct_on `ds1` \\ FULL_SIMP_TAC std_ss [APPEND,Decls_NIL]
  \\ ONCE_REWRITE_TAC [Decls_CONS]
  \\ FULL_SIMP_TAC std_ss [PULL_EXISTS,AC CONJ_COMM CONJ_ASSOC]
  \\ METIS_TAC []);

val DeclAssum_Dtype = store_thm("DeclAssum_Dtype",
  ``(!env tys. DeclAssum ds env tys ==> Eval env (Var n) P) ==>
    !tds. (!env tys. DeclAssum (SNOC (Dtype tds) ds) env tys ==>
                     Eval env (Var n) P)``,
  SRW_TAC [] []
  \\ FULL_SIMP_TAC std_ss [DeclAssum_def,SNOC_APPEND,Decls_APPEND,Decls_Dtype]
  \\ Cases_on `s2` \\ FULL_SIMP_TAC std_ss [] \\ SRW_TAC [] []
  \\ RES_TAC \\ POP_ASSUM MP_TAC
  \\ PairCases_on `env2`
  \\ SIMP_TAC std_ss [Eval_def,write_tds_def]
  \\ fs [Once evaluate_cases]
  \\ fs [Once evaluate_cases,lookup_var_id_def]);

val DeclAssum_Dlet = store_thm("DeclAssum_Dlet",
  ``!ds n P.
      (!env. DeclAssum ds env tys ==> Eval env (Var (Short n)) P) ==>
      !v e. ~(v = n) ==> (!env. DeclAssum (SNOC (Dlet (Pvar v) e) ds) env tys ==>
            Eval env (Var (Short n)) P)``,
  rw []
  \\ fs [DeclAssum_def, SNOC_APPEND,Decls_APPEND,Decls_Dlet]
  \\ PairCases_on `env2`
  \\ fs [APPEND,bind_def,Eval_Var_SIMP, merge_def,emp_def,write_def]
  \\ rw []
  \\ FIRST_X_ASSUM match_mp_tac
  \\ rw [DeclAssum_def]
  \\ Cases_on `s2` \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [GSYM empty_store_def]
  \\ IMP_RES_TAC evaluate_empty_store
  \\ FULL_SIMP_TAC std_ss [empty_store_def, Decls_def]
  \\ metis_tac [decs_unclocked]);

val DeclAssum_Dletrec_LEMMA = prove(
  ``!funs xs.
      ~MEM n (MAP FST funs) ==>
      (lookup n (FOLDR (\(x1,x2,x3) x4. bind x1 (P x1 x2 x3 x4) x4) xs funs) =
       lookup n xs)``,
  Induct
  \\ rw []
  \\ FULL_SIMP_TAC (srw_ss()) [FOLDR,FORALL_PROD,lookup_def,bind_def,MEM,MAP]
  \\ PairCases_on `h`
  \\ fs []);

val PULL_EXISTS = save_thm("PULL_EXISTS",
  METIS_PROVE [] ``(((?x. P x) ==> Q) = !x. P x ==> Q) /\
                   (((?x. P x) /\ Q) = ?x. P x /\ Q) /\
                   ((Q /\ (?x. P x)) = ?x. Q /\ P x)``);

val option_CASE_LEMMA = prove(
  Pmatch.with_classic_heuristic Term
  `!topt. (case topt of NONE => NONE | SOME t => NONE) = NONE`,
  Cases \\ SRW_TAC [] []);

val DeclAssum_Dletrec = store_thm("DeclAssum_Dletrec",
  ``!ds n P.
      (!env. DeclAssum ds env tys ==> Eval env (Var (Short n)) P) ==>
      !funs. ~(MEM n (MAP FST funs)) ==>
             (!env. DeclAssum (SNOC (Dletrec funs) ds) env tys ==>
                    Eval env (Var (Short n)) P)``,
  rw [] \\ fs [DeclAssum_def,SNOC_APPEND,Decls_APPEND,Decls_Dletrec]
  \\ PairCases_on `env2`
  \\ RES_TAC
  \\ FULL_SIMP_TAC std_ss [Eval_def]
  \\ Q.EXISTS_TAC `res` \\ FULL_SIMP_TAC std_ss []
  \\ POP_ASSUM (K ALL_TAC)
  \\ POP_ASSUM MP_TAC
  \\ ONCE_REWRITE_TAC [evaluate_cases]
  \\ FULL_SIMP_TAC (srw_ss()) [lookup_var_id_def,write_rec_def]
  \\ SIMP_TAC std_ss [Once EQ_SYM_EQ]
  \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [build_rec_env_def]
  \\ ASM_SIMP_TAC std_ss [DeclAssum_Dletrec_LEMMA]);

val DeclAssum_Dlet_INTRO = store_thm("DeclAssum_Dlet_INTRO",
  ``(!env. DeclAssum ds env tys ==> Eval env exp P) ==>
    (!v env. DeclAssum (SNOC (Dlet (Pvar v) exp) ds) env tys ==>
             Eval env (Var (Short v)) P)``,
  rw [DeclAssum_def,SNOC_APPEND,PULL_EXISTS,Decls_Dlet,Decls_APPEND]
  \\ FULL_SIMP_TAC std_ss [GSYM empty_store_def]
  \\ Cases_on `s2` \\ FULL_SIMP_TAC std_ss []
  \\ Cases_on `q` \\ FULL_SIMP_TAC std_ss []
  \\ IMP_RES_TAC evaluate_empty_store
  \\ FULL_SIMP_TAC std_ss [empty_store_def]
  \\ `q' = 0` by metis_tac [big_unclocked]
  \\ FULL_SIMP_TAC std_ss []
  \\ RES_TAC
  \\ FULL_SIMP_TAC std_ss [Eval_Var_SIMP]
  \\ FULL_SIMP_TAC std_ss [Eval_def]
  \\ FULL_SIMP_TAC std_ss [empty_store_def]
  \\ IMP_RES_TAC evaluate_11_Rval
  \\ FULL_SIMP_TAC std_ss []);

val DeclAssum_Dletrec_INTRO_ALT = store_thm("DeclAssum_Dletrec_INTRO_ALT",
  ``!funs.
      (!env1 env.
        DeclAssum ds env tys /\
        EVERY ( \ (b,P,(v,rest)).
          LOOKUP_VAR v env1 (Recclosure env (MAP (SND o SND) funs) v)) funs ==>
        EVERY ( \ (b,P,(v,rest)).
          b ==> Eval env1 (Var (Short v)) P) funs) ==>
      !env. DeclAssum (SNOC (Dletrec (MAP (SND o SND) funs)) ds) env tys ==>
            EVERY ( \ (b,P,(v,rest)).
              b ==> Eval env (Var (Short v)) P) funs``,
  STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [DeclAssum_def,SNOC_APPEND,Decls_APPEND,Decls_Dletrec,
       MAP,ALL_DISTINCT,MEM,PULL_EXISTS,build_rec_env_def,FOLDR,bind_def,
       Eval_Var_SIMP,LOOKUP_VAR_SIMP,EVERY_MEM,write_rec_def]
  \\ SIMP_TAC std_ss [Eval_def] \\ ONCE_REWRITE_TAC [evaluate_cases]
  \\ SIMP_TAC (srw_ss()) [] \\ REPEAT STRIP_TAC
  \\ PairCases_on `e`
  \\ FULL_SIMP_TAC std_ss [PULL_FORALL,AND_IMP_INTRO,lookup_var_id_def]
  \\ FULL_SIMP_TAC (srw_ss()) [] \\ REPEAT STRIP_TAC
  \\ Q.PAT_ASSUM `!env1.bbb` (MP_TAC o
       Q.GENL [`env1`,`env`,`e1`,`e2`,`e3`,`e4`] o
       Q.SPECL [`env1`,`env`,`(e1,e2,e3,e4)`])
  \\ FULL_SIMP_TAC (srw_ss()) [] \\ REPEAT STRIP_TAC
  \\ POP_ASSUM MATCH_MP_TAC
  \\ Q.EXISTS_TAC `e3,e4` \\ FULL_SIMP_TAC std_ss []
  \\ Q.EXISTS_TAC `env2` \\ FULL_SIMP_TAC std_ss []
  \\ FULL_SIMP_TAC std_ss [FORALL_PROD]
  \\ NTAC 6 STRIP_TAC
  \\ Q.MATCH_ASSUM_RENAME_TAC `MEM (b,P,v,x,y) funs` []
  \\ PairCases_on `env2`
  \\ FULL_SIMP_TAC std_ss [write_rec_def,build_rec_env_def]
  \\ Q.SPEC_TAC (`Recclosure (env20,(env21,env22),env23) (MAP (SND o SND) funs)`,
                 `recc`) \\ STRIP_TAC
  \\ POP_ASSUM MP_TAC
  \\ REPEAT (POP_ASSUM (K ALL_TAC))
  \\ Induct_on `funs` \\ FULL_SIMP_TAC std_ss [MEM,FORALL_PROD,MAP,FOLDR]
  \\ NTAC 5 STRIP_TAC
  \\ Cases_on `(v = p_1'')` \\ FULL_SIMP_TAC std_ss []
  \\ STRIP_TAC
  THEN1 (EVAL_TAC \\ FULL_SIMP_TAC std_ss [bind_def])
  THEN1 (EVAL_TAC \\ FULL_SIMP_TAC std_ss [bind_def])
  \\ FULL_SIMP_TAC std_ss [LOOKUP_VAR_def,lookup_var_def,lookup_def,bind_def]);

val DeclAssum_Dletrec_INTRO = store_thm("DeclAssum_Dletrec_INTRO",
  ``(!env1 env.
       DeclAssum ds env tys /\
       LOOKUP_VAR v env1 (Recclosure env [(v,xs,f)] v) ==>
       Eval env1 (Var (Short v)) P) ==>
    !env. DeclAssum (SNOC (Dletrec [(v,xs,f)]) ds) env tys ==>
          Eval env (Var (Short v)) P``,
  (DeclAssum_Dletrec_INTRO_ALT |> Q.SPEC `[(T,P,v,xs,f)]`
    |> SIMP_RULE std_ss [EVERY_DEF,MAP] |> ASSUME_TAC)
  \\ FULL_SIMP_TAC std_ss []);

(* a few misc. lemmas that help the automation *)

val IMP_PreImp = store_thm("IMP_PreImp",
  ``!b1 b2 b3. (b1 /\ b2 ==> b3) ==> b1 ==> PreImp b2 b3``,
  REPEAT Cases \\ EVAL_TAC);

val evaluate_list_SIMP = store_thm("evaluate_list_SIMP",
  ``(evaluate_list F env (c,empty_store) [] ((c,empty_store),Rval ([])) = T) /\
    (evaluate_list F env (c,empty_store) (x::xs) ((c,empty_store),Rval ((y::ys))) <=>
     evaluate F env (c,empty_store) x ((c,empty_store),Rval (y)) /\
     evaluate_list F env (c,empty_store) xs ((c,empty_store),Rval (ys)))``,
  REPEAT STRIP_TAC \\ SIMP_TAC std_ss [Once evaluate_cases]
  \\ FULL_SIMP_TAC (srw_ss()) []
  \\ eq_tac
  \\ rw []
  \\ METIS_TAC [big_unclocked, evaluate_list_empty_store, pair_CASES, PAIR_EQ]);

val UNCURRY1 = prove(
  ``!f. UNCURRY f = \x. case x of (x,y) => f x y``,
  STRIP_TAC \\ FULL_SIMP_TAC std_ss [FUN_EQ_THM,pair_case_def]
  \\ Cases \\ FULL_SIMP_TAC std_ss [FUN_EQ_THM,pair_case_def]);

val UNCURRY2 = prove(
  ``!x y f. pair_CASE x f y  = pair_CASE x (\z1 z2. f z1 z2 y)``,
  Cases \\ EVAL_TAC \\ SIMP_TAC std_ss []);

val UNCURRY3 = prove(
  ``pair_CASE (x,y) f = f x y``,
  EVAL_TAC) |> GEN_ALL;

val UNCURRY_SIMP = save_thm("UNCURRY_SIMP",
  LIST_CONJ [UNCURRY1,UNCURRY2,UNCURRY3]);

val num_case_thm = store_thm("num_case_thm",
  ``num_CASE = \n b f. if n = 0 then b else f (n-1)``,
  SIMP_TAC std_ss [FUN_EQ_THM,num_case_def] \\ Cases_on `n`
  \\ EVAL_TAC \\ SIMP_TAC std_ss []);

val PUSH_FORALL_INTO_IMP = save_thm("PUSH_FORALL_INTO_IMP",
  METIS_PROVE [] ``!P Q. (!x. P x ==> Q x) ==> (!x. P x) ==> (!x. Q x)``);

val FALSE_def = Define `FALSE = F`;
val TRUE_def = Define `TRUE = T`;

val MEMBER_def = Define `
  (MEMBER (x:'a) [] <=> F) /\
  (MEMBER x (y::ys) <=> (x = y) \/ MEMBER x ys)`;

val MEM_EQ_MEMBER = prove(
  ``!ys x. MEM x ys = MEMBER x ys``,
  Induct \\ FULL_SIMP_TAC (srw_ss()) [MEMBER_def]);

val MEMBER_INTRO = store_thm("MEMBER_INTRO",
  ``(MEM = MEMBER) /\ (MEM x = MEMBER x) /\ (MEM x ys = MEMBER x ys)``,
  FULL_SIMP_TAC std_ss [FUN_EQ_THM,MEM_EQ_MEMBER]);

(* DeclAssum exists *)

val DeclAssumExists_def = Define `
  DeclAssumExists ds = ?env tys. DeclAssum ds env tys`;

val SWAP_EXISTS = METIS_PROVE [] ``(?x y. P x y) ==> (?y x. P x y)``;

val DeclAssumExists_SNOC_Dtype = store_thm("DeclAssumExists_SNOC_Dtype",
  ``!funs ds.
      DeclAssumExists ds ==>
      !tds.
         (!env tys.
            DeclAssum ds env tys ==> 
            check_dup_ctors tds /\
            DISJOINT (type_defs_to_new_tdecs NONE tds) tys) ==>
         DeclAssumExists (SNOC (Dtype tds) ds)``,
  SIMP_TAC std_ss [DeclAssumExists_def,PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [DeclAssum_def,Decls_APPEND,SNOC_APPEND,Decls_Dtype]
  \\ RES_TAC \\ Q.LIST_EXISTS_TAC [`env`,`((0,[]),tys)`]
  \\ FULL_SIMP_TAC std_ss []);

val DeclAssumExists_SNOC_Dlet_Fun = store_thm("DeclAssumExists_SNOC_Dlet_Fun",
  ``!ds name n exp.
      DeclAssumExists ds ==>
      DeclAssumExists (SNOC (Dlet (Pvar name) (Fun n exp)) ds)``,
  SIMP_TAC std_ss [DeclAssumExists_def,PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [DeclAssum_def,Decls_APPEND,SNOC_APPEND]
  \\ SIMP_TAC std_ss [Decls_def] \\ ONCE_REWRITE_TAC [CONJ_COMM]
  \\ SIMP_TAC std_ss [Once evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [CONS_11,NOT_CONS_NIL,PULL_EXISTS]
  \\ SIMP_TAC (srw_ss()) [PULL_EXISTS,Once evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [PULL_EXISTS,Once evaluate_dec_cases]
  \\ SIMP_TAC (srw_ss()) [PULL_EXISTS,Once evaluate_cases]
  \\ SIMP_TAC (srw_ss()) [pmatch_def,ALL_DISTINCT,pat_bindings_def,
       combine_dec_result_def]
  \\ FULL_SIMP_TAC std_ss [Decls_def] \\ METIS_TAC []);

val DeclAssumExists_SNOC_Dlet_ALT = store_thm("DeclAssumExists_SNOC_Dlet_ALT",
  ``!ds name n exp P.
      (!env tys. DeclAssum ds env tys ==>
                 ?res. evaluate F env (0,empty_store) exp ((0,[]),Rval res)) ==>
      DeclAssumExists ds ==>
      DeclAssumExists (SNOC (Dlet (Pvar name) exp) ds)``,
  SIMP_TAC std_ss [DeclAssumExists_def,PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [DeclAssum_def,Decls_APPEND,SNOC_APPEND,PULL_EXISTS]
  \\ RES_TAC \\ SIMP_TAC std_ss [Decls_def] \\ ONCE_REWRITE_TAC [CONJ_COMM]
  \\ SIMP_TAC std_ss [Once evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [CONS_11,NOT_CONS_NIL,PULL_EXISTS]
  \\ SIMP_TAC (srw_ss()) [PULL_EXISTS,Once evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [PULL_EXISTS,Once evaluate_dec_cases]
  \\ SIMP_TAC std_ss [merge_def,APPEND_NIL]
  \\ SIMP_TAC (srw_ss()) [pmatch_def,ALL_DISTINCT,pat_bindings_def,
       combine_dec_result_def]
  \\ FULL_SIMP_TAC std_ss [Decls_def,Eval_def,PULL_EXISTS,merge_def]
  \\ RES_TAC
  \\ Q.LIST_EXISTS_TAC [`tys`,`new_tds`,`res_env`,`res'`,`(0,[])`]
  \\ FULL_SIMP_TAC std_ss [empty_store_def]);

val DeclAssumExists_SNOC_Dlet = store_thm("DeclAssumExists_SNOC_Dlet",
  ``!ds name n exp P.
      (!env tys. DeclAssum ds env tys ==> Eval env exp P) ==>
      DeclAssumExists ds ==>
      DeclAssumExists (SNOC (Dlet (Pvar name) exp) ds)``,
  NTAC 6 STRIP_TAC
  \\ MATCH_MP_TAC (GEN_ALL DeclAssumExists_SNOC_Dlet_ALT)
  \\ FULL_SIMP_TAC std_ss [Eval_def]
  \\ REPEAT STRIP_TAC \\ RES_TAC
  \\ FULL_SIMP_TAC std_ss [empty_store_def] \\ METIS_TAC []);

val DeclAssumExists_SNOC_Dletrec = store_thm("DeclAssumExists_SNOC_Dletrec",
  ``!funs ds.
      ALL_DISTINCT (MAP FST funs) ==>
      DeclAssumExists ds ==>
      DeclAssumExists (SNOC (Dletrec funs) ds)``,
  SIMP_TAC std_ss [DeclAssumExists_def,PULL_EXISTS] \\ REPEAT STRIP_TAC
  \\ FULL_SIMP_TAC std_ss [DeclAssum_def,Decls_APPEND,SNOC_APPEND]
  \\ HO_MATCH_MP_TAC SWAP_EXISTS \\ Q.EXISTS_TAC `tys`
  \\ HO_MATCH_MP_TAC SWAP_EXISTS \\ Q.EXISTS_TAC `env`
  \\ HO_MATCH_MP_TAC SWAP_EXISTS \\ Q.EXISTS_TAC `((0,[]),tys)`
  \\ FULL_SIMP_TAC std_ss [] \\ SIMP_TAC std_ss [merge_def,APPEND_NIL]
  \\ SIMP_TAC std_ss [Decls_def]
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [CONS_11,NOT_CONS_NIL,PULL_EXISTS]
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [CONS_11,NOT_CONS_NIL,PULL_EXISTS]
  \\ ONCE_REWRITE_TAC [evaluate_decs_cases]
  \\ SIMP_TAC (srw_ss()) [CONS_11,NOT_CONS_NIL,PULL_EXISTS]
  \\ ONCE_REWRITE_TAC [evaluate_dec_cases]
  \\ SIMP_TAC (srw_ss()) [CONS_11,NOT_CONS_NIL,PULL_EXISTS]
  \\ PairCases_on `env` \\ FULL_SIMP_TAC std_ss []
  \\ `ALL_DISTINCT (MAP (λ(x,y,z). x) funs)` by ALL_TAC THEN1
   (Induct_on `funs` THEN1 EVAL_TAC
    \\ Cases \\ ASM_SIMP_TAC (srw_ss()) [MEM_MAP,FORALL_PROD]
    \\ CONV_TAC (DEPTH_CONV (PairRules.PBETA_CONV))
    \\ ASM_SIMP_TAC (srw_ss()) [MEM_MAP,FORALL_PROD])
  \\ FULL_SIMP_TAC std_ss [] \\ EVAL_TAC \\ SIMP_TAC std_ss []);

val DeclAssumExists_NIL = store_thm("DeclAssumExists_NIL",
  ``DeclAssumExists []``,
  SIMP_TAC (srw_ss()) [PULL_EXISTS,Once evaluate_decs_cases,
     DeclAssumExists_def,DeclAssum_def,Decls_def]);

(* lookup cons *)

val lookup_cons_write = store_thm("lookup_cons_write",
  ``!funs n x env name.
      (lookup_cons name (write n x env) = lookup_cons name env) /\ 
      (lookup_cons name (write_rec funs env) = lookup_cons name env)``,
  Induct \\ REPEAT STRIP_TAC \\ PairCases_on `env`
  \\ FULL_SIMP_TAC std_ss [write_rec_def,write_def,lookup_cons_def]);

val _ = export_theory();
