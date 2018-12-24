(*
  Functions for constructing a CakeML program (a list of declarations) together
  with the semantic environment resulting from evaluation of the program.
*)
structure ml_progLib :> ml_progLib =
struct

open preamble;
open ml_progTheory astSyntax packLib alist_treeLib comparisonTheory;

(* state *)

datatype ml_prog_state = ML_code of (thm list) (* state const definitions *) *
                                    (thm list) (* env const definitions *) *
                                    (thm list) (* v const definitions *) *
                                    thm (* ML_code thm *);

(* converting nsLookups *)

fun pfun_eq_name const = "nsLookup_" ^ fst (dest_const const) ^ "_pfun_eqs"

val nsLookup_tm = prim_mk_const {Name = "nsLookup", Thy = "namespace"}
val nsLookup_pf_tms = [prim_mk_const {Name = "nsLookup_Mod1", Thy = "ml_prog"},
    prim_mk_const {Name = "nsLookup_Short", Thy = "ml_prog"}]

fun str_dest tm = stringSyntax.fromHOLstring tm |> explode |> map ord

val env_type = type_of (prim_mk_const {Name = "empty_env", Thy = "ml_prog"})

local

val nsLookup_repr_set = let
    val irrefl_thm = MATCH_MP good_cmp_Less_irrefl_trans string_cmp_good
  in alist_treeLib.mk_alist_reprs irrefl_thm EVAL
    str_dest (list_compare Int.compare)
  end

val empty = (Redblackmap.mkDict Term.compare : (term, unit) Redblackmap.dict)
val pfun_eqs_in_repr = ref empty

fun add thm = List.app (add_alist_repr nsLookup_repr_set) (BODY_CONJUNCTS thm)

fun get_pfun_thm c = let
    val c_details = dest_thy_const c
    val thm = DB.fetch (#Thy c_details) (pfun_eq_name c)
    (* ensure that a relevant term is present *)
    val _ = find_term (same_const (hd nsLookup_pf_tms)) (concl thm)
  in (c, thm) end

fun uniq [] = []
  | uniq [x] = [x]
  | uniq (x :: y :: zs) = if same_const x y then uniq (y :: zs)
    else x :: uniq (y :: zs)

fun mk_chain [] chain set = (chain, set)
  | mk_chain ((c, t) :: cs) chain set = if Redblackmap.peek (set, c) = SOME ()
  then mk_chain cs chain set
  else let
    val cs2 = t |> concl |> strip_conj |> map (find_terms is_const o rhs)
        |> List.concat
        |> filter (fn tm => type_of tm = env_type)
        |> Listsort.sort Term.compare |> uniq
        |> filter (fn c => Redblackmap.peek (set, c) = NONE)
        |> List.mapPartial (total get_pfun_thm)
  in if null cs2 then mk_chain cs ((c, t) :: chain)
    (Redblackmap.insert (set, c, ()))
  else mk_chain (cs2 @ (c, t) :: cs) chain set end

in

fun check_in_repr_set tms = let
    val consts = List.concat (map (find_terms is_const) tms)
        |> filter (fn tm => type_of tm = env_type)
        |> Listsort.sort Term.compare |> uniq
        |> List.mapPartial (total get_pfun_thm)
    val (chain, set) = mk_chain consts [] (! pfun_eqs_in_repr)
    val _ = if null chain then raise Empty else ()
    val chain_names = map (fst o dest_const o fst) chain
    val msg_names = if length chain > 3
        then List.take (chain_names, 2) @ ["..."] @ [List.last chain_names]
        else chain_names
    val msg = "Adding nsLookup representation thms for "
        ^ (if length chain > 3 then Int.toString (length chain) ^ " consts ["
            else "[") ^ concat (commafy msg_names) ^ "]\n"
  in
    print msg; List.app (add o snd) (rev chain);
        pfun_eqs_in_repr := set
  end handle Empty => ()

fun pfun_conv tm = let
    val (f, xs) = strip_comb tm
    val _ = length xs = 2 orelse raise UNCHANGED
    val _ = exists (same_const f) (nsLookup_tm :: nsLookup_pf_tms)
        orelse raise UNCHANGED
    val _ = check_in_repr_set [hd xs]
  in reprs_conv nsLookup_repr_set tm end

end

val nsLookup_conv_arg1_xs = [boolSyntax.conjunction, boolSyntax.disjunction,
  boolSyntax.equality, boolSyntax.conditional, optionSyntax.option_case_tm,
  prim_mk_const {Name = "OPTION_CHOICE", Thy = "option"}]

fun nsLookup_arg1_conv conv tm = let
    val (f, xs) = strip_comb tm
    val _ = exists (same_const f) nsLookup_conv_arg1_xs orelse raise UNCHANGED
  in if length xs > 1 then RATOR_CONV (nsLookup_arg1_conv conv) tm
    else if length xs = 1 then RAND_CONV conv tm
    else raise UNCHANGED
  end

val nsLookup_rewrs = List.concat (map BODY_CONJUNCTS
    [nsLookup_eq, option_choice_f_apply, boolTheory.COND_CLAUSES,
        optionTheory.option_case_def, optionTheory.OPTION_CHOICE_def,
        boolTheory.AND_CLAUSES, boolTheory.OR_CLAUSES,
        boolTheory.REFL_CLAUSE,
        nsLookup_pf_nsBind, nsLookup_Short_nsAppend, nsLookup_Mod1_nsAppend,
        nsLookup_Short_Bind, nsLookup_Mod1_Bind, nsLookup_merge_env_eqs])

fun nsLookup_conv tm = REPEATC (BETA_CONV ORELSEC FIRST_CONV
  (map REWR_CONV nsLookup_rewrs
    @ map (RATOR_CONV o REWR_CONV) nsLookup_rewrs
    @ map QCHANGED_CONV [nsLookup_arg1_conv nsLookup_conv, pfun_conv])) tm

val () = computeLib.add_convs
    (map (fn t => (t, 2, QCHANGED_CONV nsLookup_conv)) nsLookup_pf_tms)
val () = computeLib.add_thms [nsLookup_eq] computeLib.the_compset

(* helper functions *)

val reduce_conv =
  (* this could be a custom compset, but it's easier to get the
     necessary state updates directly from EVAL
     TODO: Might need more custom rewrites for env-refactor updates
  *)
  EVAL THENC REWRITE_CONV [DISJOINT_set_simp] THENC
  EVAL THENC SIMP_CONV (srw_ss()) [] THENC EVAL;

fun prove_assum_by_conv conv th = let
  val (x,y) = dest_imp (concl th)
  val lemma = conv x
  val lemma = CONV_RULE ((RATOR_CONV o RAND_CONV) (REWR_CONV lemma)) th
  in MP lemma TRUTH
     handle HOL_ERR e => let
       val _ = print "Failed to convert:\n\n"
       val _ = print_term x
       val _ = print "\n\nto T. It only reduced to:\n\n"
       val _ = print_term (lemma |> concl |> dest_eq |> snd)
       val _ = print "\n\n"
       in failwith "prove_assum_by_conv: unable to reduce term to T"
     end
  end;

val prove_assum_by_eval = prove_assum_by_conv reduce_conv

fun is_const_str str = can prim_mk_const {Thy=current_theory(), Name=str};

fun find_name name = let
  val ns = map (#1 o dest_const) (constants (current_theory()))
  fun aux n = let
    val str = name ^ "_" ^ int_to_string n
    in if mem str ns then aux (n+1) else str end
  in aux 0 end

fun ok_char c =
  (#"0" <= c andalso c <= #"9") orelse
  (#"a" <= c andalso c <= #"z") orelse
  (#"A" <= c andalso c <= #"Z") orelse
  mem c [#"_",#"'"]

val ml_name = String.translate
  (fn c => if ok_char c then implode [c] else "c" ^ int_to_string (ord c))

fun define_abbrev for_eval name tm = let
  val name = ml_name name
  val name = (if is_const_str name then find_name name else name)
  val tm = if List.null (free_vars tm) then
             mk_eq(mk_var(name,type_of tm),tm)
           else let
             val vs = free_vars tm |> sort
               (fn v1 => fn v2 => fst (dest_var v1) <= fst (dest_var v2))
             val vars = foldr mk_pair (last vs) (butlast vs)
             val n = mk_var(name,mk_type("fun",[type_of vars, type_of tm]))
             in mk_eq(mk_comb(n,vars),tm) end
  val def_name = name ^ "_def"
  val def = (*Definition.*)new_definition(def_name,tm)
  val _ = if for_eval then computeLib.add_persistent_funs [def_name] else ()
  in def end

val ML_code_tm = prim_mk_const {Name = "ML_code", Thy = "ml_prog"}

fun dest_ML_code_block tm = let
    (* mn might or might not be a syntactic tuple,
        so make sure the list length is fixed. *)
    val (mn, elts) = pairSyntax.dest_pair tm
  in mn :: pairSyntax.strip_pair elts end

fun ML_code_blocks tm = let
    val (f, xs) = strip_comb tm
    val _ = (same_const f ML_code_tm andalso length xs = 2)
        orelse failwith "ML_code_blocks: not ML_code"
    val (block_tms, _) = listSyntax.dest_list (hd xs)
  in map dest_ML_code_block block_tms end

val ML_code_open_env = List.last o hd o ML_code_blocks

val let_conv = REWR_CONV LET_THM THENC (TRY_CONV BETA_CONV)

fun let_conv_ML_upd conv nm (th, code) = let
    val msg = "let_conv_ML_upd: " ^ nm ^ ": not let"
    val _ = is_let (concl th) orelse (print (msg ^ ":\n\n");
        print_thm th; failwith msg)
    val th = CONV_RULE (RAND_CONV conv THENC let_conv) th
  in (th, code) end

fun cond_let_abbrev cond for_eval name conv op_nm th = let
    val msg = "cond_let_abbrev: " ^ op_nm ^ ": not let"
    val _ = is_let (concl th) orelse (print (msg ^ ":\n\n");
        print_thm th; failwith msg)
    val th = CONV_RULE (RAND_CONV conv) th
    val (_, tm) = dest_let (concl th)
    val (f, xs) = strip_comb tm
  in if cond andalso is_const f andalso all is_var xs
     then (CONV_RULE let_conv th, [])
     else let
       val def = define_abbrev for_eval (find_name name) tm |> SPEC_ALL
       in (CONV_RULE (RAND_CONV (REWR_CONV (GSYM def))
           THENC let_conv) th, [def])
       end
  end

fun auto_name sfx = current_theory () ^ "_" ^ sfx

fun let_st_abbrev conv op_nm (th, ML_code (ss, envs, vs, ml_th)) = let
    val (th, abbrev_defs) = cond_let_abbrev true true
        (auto_name "st") conv op_nm th
  in (th, ML_code (abbrev_defs @ ss, envs, vs, ml_th)) end

fun derive_nsLookup_thms def = let
    val env_const = def |> concl |> dest_eq |> fst
    (* derive nsLookup thms *)
    val xs = nsLookup_eq_format |> SPEC env_const |> concl
                |> find_terms is_eq |> map (fst o dest_eq)
    val rewrs = [def, nsLookup_write_eqs, nsLookup_write_cons_eqs,
                      nsLookup_merge_env_eqs, nsLookup_write_mod_eqs,
                      nsLookup_empty_eqs]
    val pfun_eqs = LIST_CONJ (map (REWRITE_CONV rewrs) xs)
    val thm_name = "nsLookup_" ^ fst (dest_const env_const) ^ "_pfun_eqs"
  in save_thm (thm_name, pfun_eqs) end

fun let_env_abbrev conv op_nm (th, ML_code (ss, envs, vs, ml_th)) = let
    val (th, abbrev_defs) = cond_let_abbrev true false
        (auto_name "env") conv op_nm th
    val _ = map derive_nsLookup_thms abbrev_defs
  in (th, ML_code (ss, abbrev_defs @ envs, vs, ml_th)) end

fun let_v_abbrev nm conv op_nm (th, ML_code (ss, envs, vs, ml_th)) = let
    val (th, abbrev_defs) = cond_let_abbrev false true nm conv op_nm th
  in (th, ML_code (ss, envs, abbrev_defs @ vs, ml_th)) end

fun solve_ml_imp f nm (th, ML_code code) = let
    val msg = "solve_ml_imp: " ^ nm ^ ": not imp"
    val _ = is_imp (concl th) orelse (print (msg ^ "\n\n");
        print_term (concl th); failwith msg)
  in (f th, ML_code code) end
fun solve_ml_imp_mp lemma = solve_ml_imp (fn th => MATCH_MP th lemma)
fun solve_ml_imp_conv conv = solve_ml_imp (prove_assum_by_conv conv)

(*
val (ML_code (ss,envs,vs,th)) = (ML_code (ss,envs,v_def :: vs,th))
*)

fun ML_code_upd nm mp_thm adjs (ML_code code) = let
    (* when updating an ML_code thm by forward resolution, first
       abstract any snoc-lists to variables, do all processing on
       that theorem, then resolve with the original in one MATCH_MP,
       which avoids traversing the snoc-list at any point. *)
    fun abs_snocs i tm = if listSyntax.is_snoc tm
        then (i + 1, mk_var ("snoc_var_" ^ Int.toString i, type_of tm))
        else if is_comb tm then let
          val (f, x) = dest_comb tm
          val (j, f) = abs_snocs i f
          val (j, x) = abs_snocs j x
        in if j = i then (i, tm) else (j, mk_comb (f, x)) end
        else (i, tm)
    val orig_th = #4 code
    val (_, no_snoc_tm) = abs_snocs 1 (concl orig_th)
    val preproc_th = MATCH_MP mp_thm (ASSUME no_snoc_tm)
    val (proc_th, ML_code (ss, envs, vs, _))
        = foldl (fn (adj, x) => adj nm x) (preproc_th, ML_code code) adjs
    val _ = same_const ML_code_tm (fst (strip_comb (concl proc_th)))
        orelse failwith ("ML_code_upd: " ^ nm ^ ": unfinished: "
            ^ Parse.thm_to_string proc_th)
    val th = MATCH_MP (DISCH no_snoc_tm proc_th) orig_th
  in ML_code (ss, envs, vs, th) end

(* --- *)

val unknown_loc = locationTheory.unknown_loc_def |> concl |> dest_eq |> fst;
val loc = unknown_loc;

val init_state =
  ML_code ([SPEC_ALL init_state_def],[init_env_def],[],ML_code_NIL);

fun open_module mn_str = ML_code_upd "open_module"
    (SPEC (stringSyntax.fromMLstring mn_str) ML_code_new_module)
    [let_env_abbrev reduce_conv]

fun close_module sig_opt = ML_code_upd "close_module"
    ML_code_close_module [let_env_abbrev reduce_conv]

(*
val tds_tm = ``[]:type_def``
*)

fun add_Dtype loc tds_tm = ML_code_upd "add_Dtype"
    (SPECL [tds_tm, loc] ML_code_Dtype)
    [solve_ml_imp_conv EVAL, let_conv_ML_upd EVAL,
        let_st_abbrev reduce_conv,
        let_env_abbrev (SIMP_CONV std_ss
            [write_tdefs_def,MAP,FLAT,FOLDR,REVERSE_DEF,
                write_conses_def,LENGTH,
                semanticPrimitivesTheory.build_constrs_def,
                APPEND,namespaceTheory.mk_id_def]
            THENC reduce_conv)]

(*
val loc = unknown_loc
val n_tm = ``"bar"``
val l_tm = ``[]:ast_t list``
*)

fun add_Dexn loc n_tm l_tm = ML_code_upd "add_Dexn"
    (SPECL [n_tm, l_tm, loc] ML_code_Dexn)
    [let_conv_ML_upd EVAL, let_st_abbrev reduce_conv,
        let_env_abbrev (SIMP_CONV std_ss [MAP,
                               FLAT,FOLDR,REVERSE_DEF,
                               APPEND,namespaceTheory.mk_id_def]
            THENC reduce_conv)]

fun add_Dtabbrev loc l1_tm l2_tm l3_tm = ML_code_upd "add_Dtabbrev"
    (SPECL [l1_tm,l2_tm,l3_tm,loc] ML_code_Dtabbrev) []

fun add_Dlet eval_thm var_str v_thms = let
    val (_, eval_thm_xs) = strip_comb (concl eval_thm)
    val e_s3_x = rev (List.take (rev eval_thm_xs, 3))
    val mp_thm = ML_code_Dlet_var |> SPECL (e_s3_x
        @ [stringSyntax.fromMLstring var_str,unknown_loc])
  in ML_code_upd "add_Dlet" mp_thm
    [solve_ml_imp_mp eval_thm, let_env_abbrev reduce_conv,
        let_st_abbrev reduce_conv]
  end

(*
val (ML_code (ss,envs,vs,th)) = s
val (n,v,exp) = (v_tm,w,body)
*)

fun add_Dlet_Fun loc n v exp v_name = ML_code_upd "add_Dlet_Fun"
    (SPECL [n, v, exp, loc] ML_code_Dlet_Fun)
    [let_v_abbrev v_name ALL_CONV, let_env_abbrev reduce_conv]

val Recclosure_pat =
  semanticPrimitivesTheory.v_nchotomy
  |> concl |> find_term (fn tm => total (fst o dest_const o fst o strip_comb
        o snd o dest_eq) tm = SOME "Recclosure")
  |> dest_eq |> snd

fun add_Dletrec loc funs v_names = let
    fun proc nm (th, (ML_code (ss,envs,vs,mlth))) = let
        val th = CONV_RULE (RAND_CONV (SIMP_CONV std_ss [write_rec_def,FOLDR,
            semanticPrimitivesTheory.build_rec_env_def])) th
        val _ = is_let (concl th) orelse failwith "add_Dletrec: not let"
        val (_, tm) = dest_let (concl th)
        val tms = rev (find_terms (can (match_term Recclosure_pat)) tm)
        val xs = zip v_names tms
        val v_defs = map (fn (x,y) => define_abbrev false x y) xs
        val th = CONV_RULE (RAND_CONV (REWRITE_CONV (map GSYM v_defs))) th
      in let_env_abbrev reduce_conv nm
        (th, ML_code (ss,envs,v_defs @ vs,mlth)) end
  in ML_code_upd "add_Dletrec"
    (SPECL [funs, loc] ML_code_Dletrec) [solve_ml_imp_conv EVAL, proc]
  end

fun get_open_modules (ML_code (ss,envs,vs,th))
  = List.mapPartial (total (apfst stringSyntax.fromHOLstring
        o pairSyntax.dest_pair o hd)) (ML_code_blocks (concl th))
    |> filter (fn ("Module", _) => true | _ => false)
    |> map (stringSyntax.fromHOLstring o snd)
    |> rev

fun get_mod_prefix code = case get_open_modules code of [] => ""
  | (m :: _) => m ^ "_"

(*
val dec_tm = dec1_tm
*)

fun add_dec dec_tm pick_name s =
  if is_Dexn dec_tm then let
    val (loc,x1,x2) = dest_Dexn dec_tm
    in add_Dexn loc x1 x2 s end
  else if is_Dtype dec_tm then let
    val (loc,x1) = dest_Dtype dec_tm
    in add_Dtype loc x1 s end
  else if is_Dtabbrev dec_tm then let
    val (loc,x1,x2,x3) = dest_Dtabbrev dec_tm
    in add_Dtabbrev loc x1 x2 x3 s end
  else if is_Dletrec dec_tm then let
    val (loc,x1) = dest_Dletrec dec_tm
    val prefix = get_mod_prefix s
    fun f str = prefix ^ pick_name str ^ "_v"
    val xs = listSyntax.dest_list x1 |> fst
               |> map (f o stringSyntax.fromHOLstring o rand o rator)
    in add_Dletrec loc x1 xs s end
  else if is_Dlet dec_tm
          andalso is_Fun (rand dec_tm)
          andalso is_Pvar (rand (rator dec_tm)) then let
    val (loc,p,f) = dest_Dlet dec_tm
    val v_tm = dest_Pvar p
    val (w,body) = dest_Fun f
    val prefix = get_mod_prefix s
    val v_name = prefix ^ pick_name (stringSyntax.fromHOLstring v_tm) ^ "_v"
    in add_Dlet_Fun loc v_tm w body v_name s end
  else if is_Dmod dec_tm then let
    val (name,(*spec,*)decs) = dest_Dmod dec_tm
    val ds = fst (listSyntax.dest_list decs)
    val name_str = stringSyntax.fromHOLstring name
    val s = open_module name_str s handle HOL_ERR _ =>
            failwith ("add_top: failed to open module " ^ name_str)
    fun each [] s = s
      | each (d::ds) s = let
           val s = add_dec d pick_name s handle HOL_ERR e =>
                   failwith ("add_top: in module " ^ name_str ^
                             "failed to add " ^ term_to_string d ^ "\n " ^
                             #message e)
           in each ds s end
    val s = each ds s
    val spec = (* SOME (optionSyntax.dest_some spec)
                  handle HOL_ERR _ => *) NONE
    val s = close_module spec s handle HOL_ERR e =>
            failwith ("add_top: failed to close module " ^ name_str ^ "\n " ^
                             #message e)
    in s end
  else failwith("add_dec does not support this shape: " ^ term_to_string dec_tm);

fun remove_snocs (ML_code (ss,envs,vs,th)) = let
  val th = th |> PURE_REWRITE_RULE [listTheory.SNOC_APPEND]
              |> PURE_REWRITE_RULE [GSYM listTheory.APPEND_ASSOC]
              |> PURE_REWRITE_RULE [listTheory.APPEND]
  in (ML_code (ss,envs,vs,th)) end

fun get_thm (ML_code (ss,envs,vs,th)) = th
fun get_v_defs (ML_code (ss,envs,vs,th)) = vs

val merge_env_tm = prim_mk_const {Name = "merge_env", Thy = "ml_prog"}

fun get_env s = let
  val th = get_thm s
  val (env1, env2) = case hd (ML_code_blocks (concl th)) of
    [_, env1, _, _, env2] => (env1, env2)
    | _ => failwith("thm concl unexpected: " ^ Parse.thm_to_string th)
  in list_mk_icomb (merge_env_tm, [env2, env1]) end

fun get_state s = get_thm s |> concl |> rand

fun get_next_type_stamp s =
  semanticPrimitivesTheory.state_component_equality
  |> ISPEC (get_state s)
  |> SPEC (get_state s)
  |> concl |> rand |> rand |> rand |> rand |> rator |> rand |> rand
  |> QCONV EVAL |> concl |> rand |> numSyntax.int_of_term;

fun get_next_exn_stamp s =
  semanticPrimitivesTheory.state_component_equality
  |> ISPEC (get_state s)
  |> SPEC (get_state s)
  |> concl |> rand |> rand |> rand |> rand |> rand |> rand
  |> QCONV EVAL |> concl |> rand |> numSyntax.int_of_term;

fun add_prog prog_tm pick_name s = let
  val ts = fst (listSyntax.dest_list prog_tm)
  in remove_snocs (foldl (fn (x,y) => add_dec x pick_name y) s ts) end

fun pack_ml_prog_state (ML_code (ss,envs,vs,th)) =
  pack_4tuple (pack_list pack_thm) (pack_list pack_thm)
    (pack_list pack_thm) pack_thm (ss,envs,vs,th)

fun unpack_ml_prog_state th =
  ML_code (unpack_4tuple (unpack_list unpack_thm) (unpack_list unpack_thm)
    (unpack_list unpack_thm) unpack_thm th)

fun clean_state (ML_code (ss,envs,vs,th)) = let
  fun FIRST_CONJUNCT th = CONJUNCTS th |> hd handle HOL_ERR _ => th
  fun delete_def def = let
    val {Name,Thy,Ty} =
      def |> SPEC_ALL |> FIRST_CONJUNCT |> SPEC_ALL |> concl
          |> dest_eq |> fst |> repeat rator |> dest_thy_const
    in if not (Thy = Theory.current_theory()) then ()
       else Theory.delete_binding (Name ^ "_def") end
  fun split x = ([hd x], tl x) handle Empty => (x,x)
  fun dd ls = let val (ls,ds) = split ls in app delete_def ds; ls end
  val () = app delete_def vs
  in (ML_code (dd ss, dd envs, [], th)) end

fun pick_name str =
  if str = "<" then "lt" else
  if str = ">" then "gt" else
  if str = "<=" then "le" else
  if str = ">=" then "ge" else
  if str = "=" then "eq" else
  if str = "<>" then "neq" else
  if str = "~" then "uminus" else
  if str = "+" then "plus" else
  if str = "-" then "minus" else
  if str = "*" then "times" else
  if str = "/" then "div" else
  if str = "!" then "deref" else
  if str = ":=" then "assign" else
  if str = "@" then "append" else
  if str = "^" then "strcat" else
  if str = "<<" then "lsl" else
  if str = ">>" then "lsr" else
  if str = "~>>" then "asr" else str (* name is fine *)

(*

val s = init_state
val dec1_tm = ``Dlet (ARB 1) (Pvar "f") (Fun "x" (Var (Short "x")))``
val dec2_tm = ``Dlet (ARB 2) (Pvar "g") (Fun "x" (Var (Short "x")))``
val prog_tm = ``[^dec1_tm; ^dec2_tm]``

val s = (add_prog prog_tm pick_name init_state)

val th = get_env s

*)

end
