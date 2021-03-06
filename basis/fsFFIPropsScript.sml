(*
  Lemmas about the file system model used by the proof about TextIO.
*)
open preamble mlstringTheory cfHeapsBaseTheory fsFFITheory MarshallingTheory

val _ = new_theory"fsFFIProps"

val _ = option_monadsyntax.temp_add_option_monadsyntax();

val option_case_eq =
    prove_case_eq_thm  { nchotomy = option_nchotomy, case_def = option_case_def}

Theorem numchars_self
  `!fs. fs = fs with numchars := fs.numchars`
  (cases_on`fs` >> fs[fsFFITheory.IO_fs_numchars_fupd]);

(* we can actually open a file if the OS limit has not been reached and we can
* still encode the file descriptor on 8 bits *)
val _ = overload_on("hasFreeFD",``λfs. CARD (set (MAP FST fs.infds)) < MIN fs.maxFD (256**8)``);

(* nextFD lemmas *)

Theorem nextFD_ltX
  `CARD (set (MAP FST fs.infds)) < x ⇒ nextFD fs < x`
  (simp[nextFD_def] >> strip_tac >> numLib.LEAST_ELIM_TAC >> simp[] >>
  qabbrev_tac `ns = MAP FST fs.infds` >> RM_ALL_ABBREVS_TAC >> conj_tac
  >- (qexists_tac `MAX_SET (set ns) + 1` >>
      pop_assum kall_tac >> DEEP_INTRO_TAC MAX_SET_ELIM >> simp[] >>
      rpt strip_tac >> res_tac >> fs[]) >>
  rpt strip_tac >> spose_not_then assume_tac >>
  `count x ⊆ set ns` by simp[SUBSET_DEF] >>
  `x ≤ CARD (set ns)`
     by metis_tac[CARD_COUNT, CARD_SUBSET, FINITE_LIST_TO_SET] >>
  fs[]);

Theorem nextFD_leX
  `CARD (set (MAP FST fs.infds)) ≤ x ⇒ nextFD fs ≤ x`
  (simp[nextFD_def] >> strip_tac >> numLib.LEAST_ELIM_TAC >> simp[] >>
  qabbrev_tac `ns = MAP FST fs.infds` >> RM_ALL_ABBREVS_TAC >> conj_tac
  >- (qexists_tac `MAX_SET (set ns) + 1` >>
      pop_assum kall_tac >> DEEP_INTRO_TAC MAX_SET_ELIM >> simp[] >>
      rpt strip_tac >> res_tac >> fs[]) >>
  rpt strip_tac >> spose_not_then assume_tac >>
  `count x PSUBSET set ns` by (
    simp[PSUBSET_DEF,SUBSET_DEF] >>
    simp[EXTENSION] \\
    qexists_tac`x` \\ simp[] ) \\
  `x < CARD (set ns)`
     by metis_tac[CARD_COUNT, CARD_PSUBSET, FINITE_LIST_TO_SET] >>
  fs[]);

Theorem nextFD_NOT_MEM
  `∀f m n fs. ¬MEM (nextFD fs,f,m,n) fs.infds`
  (rpt gen_tac >> simp[nextFD_def] >> numLib.LEAST_ELIM_TAC >> conj_tac
  >- (qexists_tac `MAX_SET (set (MAP FST fs.infds)) + 1` >>
      DEEP_INTRO_TAC MAX_SET_ELIM >>
      simp[MEM_MAP, EXISTS_PROD, FORALL_PROD] >> rw[] >> strip_tac >>
      res_tac >> fs[]) >>
  simp[EXISTS_PROD, FORALL_PROD, MEM_MAP]);

Theorem nextFD_numchars
 `!fs ll. nextFD (fs with numchars := ll) = nextFD fs`
  (rw[nextFD_def]);

(* bumpFD lemmas *)

Theorem bumpFD_numchars
 `!fs fd n ll. bumpFD fd (fs with numchars := ll) n =
        (bumpFD fd fs n) with numchars := THE (LTL ll)`
    (fs[bumpFD_def]);

Theorem bumpFD_files[simp]
  `(bumpFD fd fs n).files = fs.files`
  (EVAL_TAC \\ CASE_TAC \\ rw[]);

Theorem bumpFD_o
 `!fs fd n1 n2.
    bumpFD fd (bumpFD fd fs n1) n2 =
    bumpFD fd fs (n1 + n2) with numchars := THE (LTL (THE (LTL fs.numchars)))`
 (rw[bumpFD_def] >> cases_on`fs` >> fs[IO_fs_component_equality] >>
 fs[ALIST_FUPDKEY_o] >> irule ALIST_FUPDKEY_eq >> rw[] >> PairCases_on `v` >> fs[])

Theorem bumpFD_0
  `bumpFD fd fs 0 = fs with numchars := THE (LTL fs.numchars)`
  (rw[bumpFD_def,IO_fs_component_equality] \\
  match_mp_tac ALIST_FUPDKEY_unchanged \\
  simp[FORALL_PROD]);

(* validFD lemmas *)

Theorem validFD_numchars
  `!fd fs ll. validFD fd fs <=> validFD fd (fs with numchars := ll)`
  (rw[validFD_def])

Theorem validFD_bumpFD
  `validFD fd' fs ⇒ validFD fd' (bumpFD fd fs n)`
  (rw[bumpFD_def,validFD_def]);

Theorem validFD_ALOOKUP
  `validFD fd fs ==> ?v. ALOOKUP fs.infds fd = SOME v`
  (rw[validFD_def] >> cases_on`ALOOKUP fs.infds fd` >> fs[ALOOKUP_NONE]);

Theorem ALOOKUP_validFD
  `ALOOKUP fs.infds fd = SOME (fname, md, pos) ⇒ validFD fd fs`
  (rw[validFD_def] >> imp_res_tac ALOOKUP_MEM >>
  fs[MEM_MAP,EXISTS_PROD] >> metis_tac[]);

val validFileFD_def = Define`
  validFileFD fd infds ⇔
    ∃fnm md off. ALOOKUP infds fd = SOME (File fnm, md, off)`;

(* getNullTermStr lemmas *)

Theorem getNullTermStr_add_null
  `∀cs. ¬MEM 0w cs ⇒ getNullTermStr (cs++(0w::ls)) = SOME (MAP (CHR o w2n) cs)`
  (simp[getNullTermStr_def,  findi_APPEND, NOT_MEM_findi, findi_def, TAKE_APPEND])

Theorem getNullTermStr_insert_atI
  `∀cs l. LENGTH cs < LENGTH l ∧ ¬MEM 0w cs ⇒
          getNullTermStr (insert_atI (cs++[0w]) 0 l) = SOME (MAP (CHR o w2n) cs)`
  (simp[getNullTermStr_def, insert_atI_def, findi_APPEND, NOT_MEM_findi,
       findi_def, TAKE_APPEND])

(* the filesystem will always eventually allow to write something *)

val live_numchars_def = Define`
  live_numchars ns ⇔
    ¬LFINITE ns ∧
    always (eventually (λll. ∃k. LHD ll = SOME k ∧ k ≠ 0n)) ns`;

val liveFS_def = Define`
  liveFS fs ⇔ live_numchars fs.numchars`;

(* well formed file descriptor: all descriptors are <= maxFD
*  and correspond to file names in files *)

val wfFS_def = Define`
  wfFS fs =
    ((∀fd. fd ∈ FDOM (alist_to_fmap fs.infds) ⇒
         fd <= fs.maxFD ∧
         ∃fnm off. ALOOKUP fs.infds fd = SOME (fnm,off) ∧
                   fnm ∈ FDOM (alist_to_fmap fs.files))∧
    liveFS fs)
`;

Theorem wfFS_numchars
 `!fs ll. wfFS fs ==> ¬LFINITE ll ==>
          always (eventually (λll. ∃k. LHD ll = SOME k ∧ k ≠ 0)) ll ==>
          wfFS (fs with numchars := ll)`
 (fs[wfFS_def,liveFS_def,live_numchars_def]);

Theorem wfFS_LTL
 `!fs ll. wfFS (fs with numchars := ll) ==>
          wfFS (fs with numchars := THE (LTL ll))`
 (rw[wfFS_def,liveFS_def,live_numchars_def] >> cases_on `ll` >> fs[LDROP_1] >>
 imp_res_tac always_thm);

Theorem wfFS_openFile
  `wfFS fs ⇒ wfFS (openFileFS fnm fs md off)`
  (simp[openFileFS_def, openFile_def] >>
  Cases_on `nextFD fs <= fs.maxFD` >> simp[] >>
  Cases_on `ALOOKUP fs.files (File fnm)` >> simp[] >>
  dsimp[wfFS_def, MEM_MAP, EXISTS_PROD, FORALL_PROD] >> rw[] >>
  fs[liveFS_def] >> imp_res_tac ALOOKUP_EXISTS_IFF >>
  metis_tac[]);

Theorem wfFS_DELKEY[simp]
  `wfFS fs ⇒ wfFS (fs with infds updated_by A_DELKEY k)`
  (simp[wfFS_def, MEM_MAP, PULL_EXISTS, FORALL_PROD, EXISTS_PROD,
       ALOOKUP_ADELKEY,liveFS_def] >>
       metis_tac[]);

Theorem wfFS_LDROP
  `wfFS fs ==> wfFS (fs with numchars := (THE (LDROP k fs.numchars)))`
  (rw[wfFS_def,liveFS_def,live_numchars_def,always_DROP] >>
  imp_res_tac NOT_LFINITE_DROP >>
  first_x_assum (assume_tac o Q.SPEC `k`) >> fs[] >>
  metis_tac[NOT_LFINITE_DROP_LFINITE]);

Theorem wfFS_bumpFD[simp]
  `wfFS fs ⇒ wfFS (bumpFD fd fs n)`
  (simp[bumpFD_def] >>
  dsimp[wfFS_def, ALIST_FUPDKEY_ALOOKUP, option_case_eq, bool_case_eq,
        EXISTS_PROD] >>
  rw[] >- metis_tac[] >>
  cases_on`fs.numchars` >> fs[liveFS_def,live_numchars_def] >> imp_res_tac always_thm);

(* end of file is reached when the position index is the length of the file *)

val eof_def = Define`
  eof fd fsys =
    do
      (fnm,md,pos) <- ALOOKUP fsys.infds fd ;
      contents <- ALOOKUP fsys.files fnm ;
      return (LENGTH contents <= pos)
    od
`;

Theorem eof_numchars[simp]
  `eof fd (fs with numchars := ll) = eof fd fs`
  (rw[eof_def]);

Theorem wfFS_eof_EQ_SOME
  `wfFS fs ∧ validFD fd fs ⇒
   ∃b. eof fd fs = SOME b`
  (simp[eof_def, EXISTS_PROD, PULL_EXISTS, MEM_MAP, wfFS_def, validFD_def] >>
  rpt strip_tac >> res_tac >> metis_tac[ALOOKUP_EXISTS_IFF]);

(*
Theorem eof_read
 `!fd fs n. wfFS fs ⇒
            0 < n ⇒ (eof fd fs = SOME T) ⇒
            read fd fs n = SOME ([], fs with numchars := THE(LTL fs.numchars))`
 (rw[eof_def,read_def,MIN_DEF]  >>
 qexists_tac `x` >> rw[] >>
 pairarg_tac >> fs[bumpFD_def,wfFS_def] >>
 cases_on`fs.numchars` >> fs[IO_fs_component_equality,liveFS_def,live_numchars_def] >>
 irule ALIST_FUPDKEY_unchanged >> cases_on`v` >> rw[]);
*)

Theorem eof_read
 `!fd fs n fs'. 0 < n ⇒ read fd fs n = SOME ([], fs') ⇒ eof fd fs = SOME T`
 (rw[eof_def,read_def] >>
 qexists_tac `x` >> rw[] >>
 PairCases_on `x` >>
 fs[DROP_NIL]);

(*
Theorem neof_read
  `eof fd fs = SOME F ⇒ 0 < n ⇒
     wfFS fs ⇒
     ∃l fs'. l <> "" /\ read fd fs n = SOME (l,fs')`
  (mp_tac (Q.SPECL [`fd`, `fs`, `n`] read_def) >>
  rw[wfFS_def,liveFS_def,live_numchars_def] >>
  cases_on `ALOOKUP fs.infds fd` >> fs[eof_def] >>
  PairCases_on `x` >> fs[] >>
  cases_on `ALOOKUP fs.files x0` >> fs[eof_def] >>
  cases_on `fs.numchars` >> fs[] >>
  cases_on `DROP x2 contents` >> fs[] >>
  `x2 ≥ LENGTH contents` by fs[DROP_EMPTY] >>
  fs[]);
*)

Theorem get_file_content_eof
  `get_file_content fs fd = SOME (content,pos) ⇒ eof fd fs = SOME (¬(pos < LENGTH content))`
  (rw[get_file_content_def,eof_def]
  \\ pairarg_tac \\ fs[]);

(* inFS_fname *)

val inFS_fname_def = Define `
  inFS_fname fs s = (s ∈ FDOM (alist_to_fmap fs.files))`

Theorem not_inFS_fname_openFile
  `~inFS_fname fs (File fname) ⇒ openFile fname fs md off = NONE`
  (fs [inFS_fname_def, openFile_def, ALOOKUP_NONE]
  );

Theorem inFS_fname_ALOOKUP_EXISTS
  `inFS_fname fs fname ⇒ ∃content. ALOOKUP fs.files fname = SOME content`
  (fs [inFS_fname_def, MEM_MAP] >> rpt strip_tac >> fs[] >>
  rename1 `fname = FST p` >> Cases_on `p` >>
  fs[ALOOKUP_EXISTS_IFF] >> metis_tac[]);

Theorem ALOOKUP_SOME_inFS_fname
  `ALOOKUP fs.files fnm = SOME contents ==> inFS_fname fs fnm`
  (Induct_on `fs.files` >> rpt strip_tac >>
  qpat_x_assum `_ = fs.files` (assume_tac o GSYM) >> rw[] >>
  fs [inFS_fname_def] >> rename1 `fs.files = p::ps` >>
  Cases_on `p` >> fs [ALOOKUP_def] >> every_case_tac >> fs[] >> rw[] >>
  first_assum (qspec_then `fs with files := ps` assume_tac) >> fs []
);

Theorem ALOOKUP_inFS_fname_openFileFS_nextFD
  `inFS_fname fs (File f) ∧ nextFD fs <= fs.maxFD
   ⇒
   ALOOKUP (openFileFS f fs md off).infds (nextFD fs) = SOME (File f,md,off)`
  (rw[openFileFS_def,openFile_def]
  \\ imp_res_tac inFS_fname_ALOOKUP_EXISTS
  \\ rw[]);

Theorem inFS_fname_numchars
 `!s fs ll. inFS_fname (fs with numchars := ll) s = inFS_fname fs s`
  (rw[] >> EVAL_TAC >> rpt(CASE_TAC >> fs[]));

(* ffi lengths *)

Theorem ffi_open_in_length
  `ffi_open_in conf bytes fs = SOME (FFIreturn bytes' fs') ==> LENGTH bytes' = LENGTH bytes`
  (rw[ffi_open_in_def] \\ fs[option_eq_some]
  \\ TRY(pairarg_tac) \\ rw[] \\ fs[] \\ rw[] \\ fs[n2w8_def]);

Theorem ffi_open_out_length
  `ffi_open_out conf bytes fs = SOME (FFIreturn bytes' fs') ==> LENGTH bytes' = LENGTH bytes`
  (rw[ffi_open_out_def] \\ fs[option_eq_some]
  \\ TRY(pairarg_tac) \\ rw[] \\ fs[] \\ rw[] \\ fs[n2w8_def]);

Theorem read_length
    `read fd fs k = SOME (l, fs') ==> LENGTH l <= k`
    (rw[read_def] >> pairarg_tac >> fs[option_eq_some,LENGTH_TAKE] >>
    ` l  = TAKE (MIN k (MIN (STRLEN content − off) (SUC strm)))
        (DROP off content)` by (fs[]) >>
    fs[MIN_DEF,LENGTH_DROP]);

Theorem ffi_read_length
  `ffi_read conf bytes fs = SOME (FFIreturn bytes' fs') ==> LENGTH bytes' = LENGTH bytes`
  (rw[ffi_read_def]
  \\ fs[option_case_eq,prove_case_eq_thm{nchotomy=list_nchotomy,case_def=list_case_def}]
  \\ fs[option_eq_some]
  \\ TRY(pairarg_tac) \\ rveq \\ fs[] \\ rveq \\ fs[n2w2_def]
  \\ imp_res_tac read_length \\ fs[]);

Theorem ffi_write_length
  `ffi_write conf bytes fs = SOME (FFIreturn bytes' fs') ==> LENGTH bytes' = LENGTH bytes`
  (EVAL_TAC \\ rw[]
  \\ fs[option_eq_some] \\ every_case_tac \\ fs[] \\ rw[]
  \\ pairarg_tac \\ fs[] \\ pairarg_tac \\ fs[n2w2_def]
  \\ rw[] \\ Cases_on`bytes` \\ fs[]
  \\ rpt(Cases_on`t` \\ fs[] \\ Cases_on`t'` \\ fs[]));

Theorem ffi_close_length
  `ffi_close conf bytes fs = SOME (FFIreturn bytes' fs') ==> LENGTH bytes' = LENGTH bytes`
  (rw[ffi_close_def] \\ fs[option_eq_some] \\ TRY pairarg_tac \\ fs[] \\ rw[]);

(* fastForwardFD *)

val fastForwardFD_def = Define`
  fastForwardFD fs fd =
    the fs (do
      (fnm,md,off) <- ALOOKUP fs.infds fd;
      content <- ALOOKUP fs.files fnm;
      SOME (fs with infds updated_by ALIST_FUPDKEY fd (I ## I ## MAX (LENGTH content)))
    od)`;

Theorem validFD_fastForwardFD[simp]
  `validFD fd (fastForwardFD fs fd) = validFD fd fs`
  (rw[validFD_def,fastForwardFD_def,bumpFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ rw[OPTION_GUARD_COND,libTheory.the_def]);

Theorem validFileFD_fastForwardFD[simp]
  `validFileFD fd (fastForwardFD fs x).infds ⇔ validFileFD fd fs.infds`
  (rw[validFileFD_def, fastForwardFD_def]
  \\ Cases_on`ALOOKUP fs.infds x` \\ rw[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ simp[ALIST_FUPDKEY_ALOOKUP]
  \\ TOP_CASE_TAC \\ simp[]
  \\ rw[PAIR_MAP, FST_EQ_EQUIV, PULL_EXISTS, SND_EQ_EQUIV]
  \\ rw[EQ_IMP_THM]);

Theorem fastForwardFD_files[simp]
  `(fastForwardFD fs fd).files = fs.files`
  (EVAL_TAC
  \\ Cases_on`ALOOKUP fs.infds fd` \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ rw[OPTION_GUARD_COND,libTheory.the_def]);

Theorem A_DELKEY_fastForwardFD_elim[simp]
  `A_DELKEY fd (fastForwardFD fs fd).infds = A_DELKEY fd fs.infds`
  (rw[fastForwardFD_def,bumpFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ rw[OPTION_GUARD_COND,libTheory.the_def]);

Theorem fastForwardFD_A_DELKEY_same[simp]
  `fastForwardFD fs fd with infds updated_by A_DELKEY fd =
   fs with infds updated_by A_DELKEY fd`
  (rw[fastForwardFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[libTheory.the_def]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ fs[IO_fs_component_equality,A_DELKEY_I])

Theorem fastForwardFD_0
  `(∀content pos. get_file_content fs fd = SOME (content,pos) ⇒ LENGTH content ≤ pos) ⇒
   fastForwardFD fs fd = fs`
  (rw[fastForwardFD_def,get_file_content_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ fs[IO_fs_component_equality]
  \\ match_mp_tac ALIST_FUPDKEY_unchanged
  \\ rw[] \\ rw[PAIR_MAP_THM]
  \\ rw[MAX_DEF]);

Theorem fastForwardFD_with_numchars
  `fastForwardFD (fs with numchars := ns) fd = fastForwardFD fs fd with numchars := ns`
  (rw[fastForwardFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ simp[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ simp[libTheory.the_def]);

Theorem fastForwardFD_numchars[simp]
  `(fastForwardFD fs fd).numchars = fs.numchars`
  (rw[fastForwardFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ simp[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ simp[libTheory.the_def]);

Theorem fastForwardFD_maxFD[simp]
  `(fastForwardFD fs fd).maxFD = fs.maxFD`
  (rw[fastForwardFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ simp[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ simp[libTheory.the_def]);

(* fsupdate *)

Theorem wfFS_fsupdate
    `! fs fd content pos k. wfFS fs ==> MEM fd (MAP FST fs.infds) ==>
                            wfFS (fsupdate fs fd k pos content)`
  (rw[wfFS_def,fsupdate_def]
  >- (res_tac \\ fs[])
  >- (
    CASE_TAC \\ fs[] \\
    CASE_TAC \\ fs[ALIST_FUPDKEY_ALOOKUP] \\
    res_tac \\ fs[] \\ rw[] )
  >-( CASE_TAC \\ fs[] \\ CASE_TAC \\ fs[] \\
      fs[liveFS_def,live_numchars_def,always_DROP] >>
     `∃y. LDROP k fs.numchars = SOME y` by(fs[NOT_LFINITE_DROP]) >>
       fs[] >> metis_tac[NOT_LFINITE_DROP_LFINITE]));

Theorem fsupdate_unchanged
 `get_file_content fs fd = SOME(content, pos) ==>
    fsupdate fs fd 0 pos content = fs`
    (fs[fsupdate_def,get_file_content_def,validFD_def,IO_fs_component_equality]>>
    rw[] >> pairarg_tac >> fs[ALIST_FUPDKEY_unchanged] >> rw[]);

Theorem fsupdate_o
  `liveFS fs ==>
   fsupdate (fsupdate fs fd k1 pos1 c1) fd k2 pos2 c2 =
   fsupdate fs fd (k1+k2) pos2 c2`
  (rw[fsupdate_def]
  \\ CASE_TAC \\ fs[]
  \\ CASE_TAC \\ fs[]
  \\ fs[ALIST_FUPDKEY_ALOOKUP,ALIST_FUPDKEY_o] \\
  fs[LDROP_ADD,liveFS_def,live_numchars_def] >> imp_res_tac NOT_LFINITE_DROP >>
  FIRST_X_ASSUM(ASSUME_TAC o Q.SPEC`k1`) >> fs[]
  \\ rpt (AP_TERM_TAC ORELSE AP_THM_TAC)
  \\ simp[FUN_EQ_THM, FORALL_PROD]);

Theorem fsupdate_o_0[simp]
  `fsupdate (fsupdate fs fd 0 pos1 c1) fd 0 pos2 c2 =
   fsupdate fs fd 0 pos2 c2`
  (rw[fsupdate_def] \\ CASE_TAC \\ fs[] \\ CASE_TAC \\ fs[] \\
  rw[ALIST_FUPDKEY_ALOOKUP,ALIST_FUPDKEY_o]
  \\ rpt(AP_TERM_TAC ORELSE AP_THM_TAC)
  \\ simp[FUN_EQ_THM, FORALL_PROD]);

Theorem fsupdate_comm
  `!fs fd1 fd2 k1 p1 c1 fnm1 pos1 k2 p2 c2 fnm2 pos2.
     ALOOKUP fs.infds fd1 = SOME(fnm1, pos1) /\
     ALOOKUP fs.infds fd2 = SOME(fnm2, pos2) /\
  fnm1 <> fnm2 /\ fd1 <> fd2 /\ ¬ LFINITE fs.numchars ==>
  fsupdate (fsupdate fs fd1 k1 p1 c1) fd2 k2 p2 c2 =
  fsupdate (fsupdate fs fd2 k2 p2 c2) fd1 k1 p1 c1`
  (fs[fsupdate_def] >> rw[] >> fs[ALIST_FUPDKEY_ALOOKUP] >>
  rpt CASE_TAC >> fs[ALIST_FUPDKEY_comm,LDROP_LDROP]);

Theorem fsupdate_MAP_FST_infds[simp]
  `MAP FST (fsupdate fs fd k pos c).infds = MAP FST fs.infds`
  (rw[fsupdate_def] \\ every_case_tac \\ rw[]);

Theorem fsupdate_MAP_FST_files[simp]
  `MAP FST (fsupdate fs fd k pos c).files = MAP FST fs.files`
  (rw[fsupdate_def] \\ every_case_tac \\ rw[]);

Theorem validFD_fsupdate[simp]
  `validFD fd (fsupdate fs fd' x y z) ⇔ validFD fd fs`
  (rw[fsupdate_def,validFD_def]);

Theorem validFileFD_fsupdate[simp]
  `validFileFD fd (fsupdate fs fd' x y z).infds ⇔ validFileFD fd fs.infds`
  (rw[fsupdate_def,validFileFD_def]
  \\ TOP_CASE_TAC \\ simp[]
  \\ TOP_CASE_TAC \\ simp[]
  \\ simp[ALIST_FUPDKEY_ALOOKUP]
  \\ TOP_CASE_TAC \\ simp[]
  \\ rw[]
  \\ PairCases_on`x`
  \\ simp[]);

Theorem fsupdate_numchars
  `!fs fd k p c ll. fsupdate fs fd k p c with numchars := ll =
                    fsupdate (fs with numchars := ll) fd 0 p c`
  (rw[fsupdate_def] \\ CASE_TAC \\ CASE_TAC \\ rw[]);

Theorem fsupdate_A_DELKEY
  `fd ≠ fd' ⇒
   fsupdate (fs with infds updated_by A_DELKEY fd') fd k pos content =
   fsupdate fs fd k pos content with infds updated_by A_DELKEY fd'`
  (rw[fsupdate_def,ALOOKUP_ADELKEY]
  \\ CASE_TAC \\ CASE_TAC
  \\ rw[A_DELKEY_ALIST_FUPDKEY_comm]);

Theorem fsupdate_0_numchars
  `IS_SOME (ALOOKUP fs.infds fd) ⇒
   fsupdate fs fd n pos content =
   fsupdate (fs with numchars := THE (LDROP n fs.numchars)) fd 0 pos content`
  (rw[fsupdate_def] \\ TOP_CASE_TAC \\ fs[]);

Theorem fsupdate_maxFD[simp]
 `!fs fd k pos content.
   (fsupdate fs fd k pos content).maxFD = fs.maxFD`
 (rw [fsupdate_def] \\ every_case_tac \\ simp []);

(* get_file_content *)

Theorem get_file_content_numchars
 `!fs fd. get_file_content fs fd =
              get_file_content (fs with numchars := ll) fd`
 (fs[get_file_content_def]);

Theorem get_file_content_validFD
  `get_file_content fs fd = SOME(c,p) ⇒ validFD fd fs`
  (fs[get_file_content_def,validFD_def] >> rw[] >> pairarg_tac >>
  imp_res_tac ALOOKUP_MEM >> fs[ALOOKUP_MEM,MEM_MAP] >>
  qexists_tac`(fd,x)` >> fs[]);

Theorem get_file_content_fsupdate
  `!fs fd x i c u. get_file_content fs fd = SOME u ⇒
  get_file_content (fsupdate fs fd x i c) fd = SOME(c,i)`
  (rw[get_file_content_def, fsupdate_def] >>
  pairarg_tac >> fs[ALIST_FUPDKEY_ALOOKUP]);

Theorem get_file_content_fsupdate_unchanged
  `!fs fd u fnm pos fd' fnm' pos' x i c.
   get_file_content fs fd = SOME u ⇒
   ALOOKUP fs.infds fd = SOME (fnm,pos) ⇒
   ALOOKUP fs.infds fd' = SOME (fnm',pos') ⇒ fnm ≠ fnm' ⇒
  get_file_content (fsupdate fs fd' x i c) fd = SOME u`
  (rw[get_file_content_def, fsupdate_def] >>
  pairarg_tac >> fs[ALIST_FUPDKEY_ALOOKUP] >>
  rpt(CASE_TAC >> fs[]));

Theorem get_file_content_bumpFD[simp]
 `!fs fd c pos n.
   get_file_content (bumpFD fd fs n) fd =
   OPTION_MAP (I ## (+) n) (get_file_content fs fd)`
 (rw[get_file_content_def,bumpFD_def,ALIST_FUPDKEY_ALOOKUP]
 \\ CASE_TAC \\ fs[]
 \\ pairarg_tac \\ fs[]
 \\ pairarg_tac \\ fs[] \\ rw[]
 \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[]);

(* liveFS *)

Theorem liveFS_openFileFS
 `liveFS fs ⇒ liveFS (openFileFS s fs md n)`
  (rw[liveFS_def,openFileFS_def, openFile_def] >>
  CASE_TAC >> fs[] >> CASE_TAC >> fs[] >>
  `r.numchars = fs.numchars` by
    (cases_on`fs` >> cases_on`r` >> fs[IO_fs_infds_fupd]) >>
  fs[]);

Theorem liveFS_fsupdate
 `liveFS fs ⇒ liveFS (fsupdate fs fd n k c)`
 (rw[liveFS_def,live_numchars_def,fsupdate_def] >>
 every_case_tac \\ fs[always_DROP] \\
 metis_tac[NOT_LFINITE_DROP,NOT_LFINITE_DROP_LFINITE,THE_DEF]);

Theorem liveFS_bumpFD
 `liveFS fs ⇒ liveFS (bumpFD fd fs k)`
  (rw[liveFS_def,live_numchars_def,bumpFD_def] >> cases_on`fs.numchars` >> fs[] >>
  imp_res_tac always_thm);

(* openFile, openFileFS *)

Theorem openFile_fupd_numchars
 `!s fs k ll fd fs'. openFile s (fs with numchars := ll) md k =
      case openFile s fs md k of
        SOME (fd, fs') => SOME (fd, fs' with numchars := ll)
      | NONE => NONE`
  (rw[openFile_def,nextFD_def] >> rpt(CASE_TAC >> fs[]) >>
  rfs[IO_fs_component_equality]);

Theorem openFileFS_numchars
  `!s fs k. (openFileFS s fs md k).numchars = fs.numchars`
   (rw[openFileFS_def] \\ CASE_TAC \\ CASE_TAC
   \\ fs[openFile_def] \\ rw[]);

Theorem wfFS_openFileFS
  `!f fs k.CARD (FDOM (alist_to_fmap fs.infds)) <= fs.maxFD /\ wfFS fs ==>
                   wfFS (openFileFS f fs md k)`
  (rw[wfFS_def,openFileFS_def,liveFS_def] >> full_case_tac >> fs[openFile_def] >>
  cases_on`x` >> rw[] >> fs[MEM_MAP] >> res_tac >> fs[]
  >-(imp_res_tac ALOOKUP_MEM >-(qexists_tac`(File f,x')` >> fs[])) >>
  CASE_TAC
  >-(cases_on`y` >> fs[] >> PairCases_on`r` >> fs[] >> metis_tac[nextFD_NOT_MEM])
  >> metis_tac[])

Theorem openFileFS_files[simp]
 `!f fs pos. (openFileFS f fs md pos).files = fs.files`
  (rw[openFileFS_def] >> CASE_TAC >> cases_on`x` >>
  fs[IO_fs_component_equality,openFile_def]);

Theorem openFileFS_maxFD[simp]
  `(openFileFS f fs md pos).maxFD = fs.maxFD`
  (rw[openFileFS_def]
  \\ CASE_TAC
  \\ CASE_TAC
  \\ fs[openFile_def]
  \\ rw[]);

Theorem openFileFS_fupd_numchars
 `!s fs k ll. openFileFS s (fs with numchars := ll) md k =
              (openFileFS s fs md k with numchars := ll)`
  (rw[openFileFS_def,openFile_fupd_numchars] >> rpt CASE_TAC);

Theorem IS_SOME_get_file_content_openFileFS_nextFD
  `inFS_fname fs (File f) ∧ nextFD fs ≤ fs.maxFD
   ⇒ IS_SOME (get_file_content (openFileFS f fs md off) (nextFD fs)) `
  (rw[get_file_content_def]
  \\ imp_res_tac ALOOKUP_inFS_fname_openFileFS_nextFD \\ simp[]
  \\ imp_res_tac inFS_fname_ALOOKUP_EXISTS \\ fs[]);

Theorem A_DELKEY_nextFD_openFileFS[simp]
  `nextFD fs <= fs.maxFD ⇒
   A_DELKEY (nextFD fs) (openFileFS f fs md off).infds = fs.infds`
  (rw[openFileFS_def]
  \\ CASE_TAC
  \\ TRY CASE_TAC
  \\ simp[A_DELKEY_I,nextFD_NOT_MEM,MEM_MAP,EXISTS_PROD]
  \\ fs[openFile_def] \\ rw[]
  \\ rw[A_DELKEY_def,FILTER_EQ_ID,EVERY_MEM,FORALL_PROD,nextFD_NOT_MEM]);

Theorem openFileFS_A_DELKEY_nextFD
  `nextFD fs ≤ fs.maxFD ⇒
   openFileFS f fs md off with infds updated_by A_DELKEY (nextFD fs) = fs`
  (rw[IO_fs_component_equality,openFileFS_numchars,A_DELKEY_nextFD_openFileFS]);

(* forwardFD: like bumpFD but leave numchars *)

val forwardFD_def = Define`
  forwardFD fs fd n =
    fs with infds updated_by ALIST_FUPDKEY fd (I ## I ## (+) n)`;

Theorem forwardFD_const[simp]
  `(forwardFD fs fd n).files = fs.files ∧
   (forwardFD fs fd n).numchars = fs.numchars ∧
   (forwardFD fs fd n).maxFD = fs.maxFD`
  (rw[forwardFD_def]);

Theorem forwardFD_o
  `forwardFD (forwardFD fs fd n) fd m = forwardFD fs fd (n+m)`
  (rw[forwardFD_def,IO_fs_component_equality,ALIST_FUPDKEY_o]
  \\ AP_THM_TAC \\ AP_TERM_TAC
  \\ simp[FUN_EQ_THM,FORALL_PROD]);

Theorem forwardFD_0[simp]
  `forwardFD fs fd 0 = fs`
  (rw[forwardFD_def,IO_fs_component_equality]
  \\ match_mp_tac ALIST_FUPDKEY_unchanged
  \\ simp[FORALL_PROD]);

Theorem forwardFD_numchars
  `forwardFD (fs with numchars := ll) fd n = forwardFD fs fd n with numchars := ll`
  (rw[forwardFD_def]);

Theorem liveFS_forwardFD[simp]
  `liveFS (forwardFD fs fd n) = liveFS fs`
  (rw[liveFS_def]);

Theorem MAP_FST_forwardFD_infds[simp]
  `MAP FST (forwardFD fs fd n).infds = MAP FST fs.infds`
  (rw[forwardFD_def]);

Theorem validFD_forwardFD[simp]
  `validFD fd (forwardFD fs fd n)= validFD fd fs`
  (rw[validFD_def]);

Theorem wfFS_forwardFD[simp]
  `wfFS (forwardFD fs fd n) = wfFS fs`
  (rw[wfFS_def]
  \\ rw[forwardFD_def,ALIST_FUPDKEY_ALOOKUP]
  \\ rw[EQ_IMP_THM]
  \\ res_tac \\ fs[]
  \\ FULL_CASE_TAC \\ fs[]
  \\ FULL_CASE_TAC \\ fs[]
  \\ Cases_on`x` \\ fs[]);

Theorem get_file_content_forwardFD[simp]
  `!fs fd c pos n.
    get_file_content (forwardFD fs fd n) fd =
    OPTION_MAP (I ## (+) n) (get_file_content fs fd)`
  (rw[get_file_content_def,forwardFD_def,ALIST_FUPDKEY_ALOOKUP]
  \\ CASE_TAC \\ fs[]
  \\ pairarg_tac \\ fs[]
  \\ pairarg_tac \\ fs[] \\ rw[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[]);

Theorem bumpFD_forwardFD
  `bumpFD fd fs n = forwardFD fs fd n with numchars := THE (LTL fs.numchars)`
  (rw[bumpFD_def,forwardFD_def]);

Theorem fastForwardFD_forwardFD
  `get_file_content fs fd = SOME (content,pos) ∧ pos + n ≤ LENGTH content ⇒
   fastForwardFD (forwardFD fs fd n) fd = fastForwardFD fs fd`
  (rw[fastForwardFD_def,get_file_content_def,forwardFD_def,ALIST_FUPDKEY_ALOOKUP]
  \\ rw[]
  \\ pairarg_tac \\ fs[]
  \\ pairarg_tac \\ fs[libTheory.the_def]
  \\ fs[IO_fs_component_equality,ALIST_FUPDKEY_o]
  \\ match_mp_tac ALIST_FUPDKEY_eq
  \\ simp[MAX_DEF]);

Theorem forwardFD_A_DELKEY_same
  `forwardFD fs fd n with infds updated_by A_DELKEY fd = fs with infds updated_by A_DELKEY fd`
  (rw[forwardFD_def,IO_fs_component_equality]);

(* lineFD: the next line *)

val lineFD_def = Define`
  lineFD fs fd = do
    (content, pos) <- get_file_content fs fd;
    assert (pos < LENGTH content);
    let (l,r) = SPLITP ((=)#"\n") (DROP pos content) in
      SOME(l++"\n") od`;

(* linesFD: get all the lines *)

val linesFD_def = Define`
 linesFD fs fd =
   case get_file_content fs fd of
   | NONE => []
   | SOME (content,pos) =>
       MAP (λx. x ++ "\n")
         (splitlines (DROP pos content))`;

Theorem linesFD_nil_lineFD_NONE
  `linesFD fs fd = [] ⇔ lineFD fs fd = NONE`
  (rw[lineFD_def,linesFD_def]
  \\ CASE_TAC \\ fs[]
  \\ CASE_TAC \\ fs[]
  \\ pairarg_tac \\ fs[DROP_NIL]);

(* all_lines: get all the lines based on filename *)

val lines_of_def = Define `
  lines_of str =
    MAP (\x. strcat (implode x) (implode "\n"))
          (splitlines (explode str))`

val all_lines_def = Define `
  all_lines fs fname = lines_of (implode (THE (ALOOKUP fs.files fname)))`

Theorem concat_lines_of
  `!s. concat (lines_of s) = s ∨
        concat (lines_of s) = s ^ str #"\n"`
  (rw[lines_of_def] \\
  `s = implode (explode s)` by fs [explode_implode] \\
  qabbrev_tac `ls = explode s` \\ pop_assum kall_tac \\ rveq \\
  Induct_on`splitlines ls` \\ rw[] \\
  pop_assum(assume_tac o SYM) \\
  fs[splitlines_eq_nil,concat_cons]
  >- EVAL_TAC \\
  imp_res_tac splitlines_next \\ rw[] \\
  first_x_assum(qspec_then`DROP (SUC (LENGTH h)) ls`mp_tac) \\
  rw[] \\ rw[]
  >- (
    Cases_on`LENGTH h < LENGTH ls` \\ fs[] >- (
      disj1_tac \\
      rw[strcat_thm] \\ AP_TERM_TAC \\
      fs[IS_PREFIX_APPEND,DROP_APPEND,DROP_LENGTH_TOO_LONG,ADD1] ) \\
    fs[DROP_LENGTH_TOO_LONG] \\
    fs[IS_PREFIX_APPEND,strcat_thm] \\ rw[] \\ fs[] \\
    EVAL_TAC )
  >- (
    disj2_tac \\
    rw[strcat_thm] \\
    AP_TERM_TAC \\ rw[] \\
    Cases_on`LENGTH h < LENGTH ls` \\
    fs[IS_PREFIX_APPEND,DROP_APPEND,ADD1,DROP_LENGTH_TOO_LONG]  \\
    qpat_x_assum`strlit [] = _`mp_tac \\ EVAL_TAC ));

Theorem concat_all_lines
  `concat (all_lines fs fname) = implode (THE (ALOOKUP fs.files fname)) ∨
   concat (all_lines fs fname) = implode (THE (ALOOKUP fs.files fname)) ^ str #"\n"`
  (fs [all_lines_def,concat_lines_of]);

Theorem all_lines_with_numchars
  `all_lines (fs with numchars := ns) = all_lines fs`
  (rw[FUN_EQ_THM,all_lines_def]);

Theorem linesFD_openFileFS_nextFD
  `inFS_fname fs (File f) ∧ nextFD fs ≤ fs.maxFD ⇒
   linesFD (openFileFS f fs md 0) (nextFD fs) = MAP explode (all_lines fs (File f))`
  (rw[linesFD_def,get_file_content_def,ALOOKUP_inFS_fname_openFileFS_nextFD]
  \\ rw[all_lines_def,lines_of_def]
  \\ imp_res_tac inFS_fname_ALOOKUP_EXISTS
  \\ fs[MAP_MAP_o,o_DEF,GSYM mlstringTheory.implode_STRCAT]);

(* lineForwardFD: seek past the next line *)

val lineForwardFD_def = Define`
  lineForwardFD fs fd =
    case get_file_content fs fd of
    | NONE => fs
    | SOME (content, pos) =>
      if pos < LENGTH content
      then let (l,r) = SPLITP ((=)#"\n") (DROP pos content) in
        forwardFD fs fd (LENGTH l + if NULL r then 0 else 1)
      else fs`;

Theorem fastForwardFD_lineForwardFD[simp]
  `fastForwardFD (lineForwardFD fs fd) fd = fastForwardFD fs fd`
  (rw[fastForwardFD_def,lineForwardFD_def]
  \\ TOP_CASE_TAC \\ fs[libTheory.the_def]
  \\ TOP_CASE_TAC \\ fs[libTheory.the_def]
  \\ TOP_CASE_TAC \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ fs[forwardFD_def,ALIST_FUPDKEY_ALOOKUP,get_file_content_def]
  \\ pairarg_tac \\ fs[]
  \\ pairarg_tac \\ fs[libTheory.the_def]
  \\ fs[IO_fs_component_equality,ALIST_FUPDKEY_o]
  \\ match_mp_tac ALIST_FUPDKEY_eq
  \\ simp[] \\ rveq
  \\ imp_res_tac SPLITP_JOIN
  \\ pop_assum(mp_tac o Q.AP_TERM`LENGTH`)
  \\ simp[SUB_RIGHT_EQ]
  \\ rw[MAX_DEF,NULL_EQ] \\ fs[]);

Theorem IS_SOME_get_file_content_lineForwardFD[simp]
  `IS_SOME (get_file_content (lineForwardFD fs fd) fd) =
   IS_SOME (get_file_content fs fd)`
  (rw[lineForwardFD_def]
  \\ CASE_TAC \\ simp[]
  \\ CASE_TAC \\ simp[]
  \\ CASE_TAC \\ simp[]
  \\ pairarg_tac \\ simp[]);

Theorem lineFD_NONE_lineForwardFD_fastForwardFD
  `lineFD fs fd = NONE ⇒
   lineForwardFD fs fd = fastForwardFD fs fd`
  (rw[lineFD_def,lineForwardFD_def,fastForwardFD_def,get_file_content_def]
  \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[libTheory.the_def]
  \\ rveq \\ fs[libTheory.the_def]
  \\ rw[] \\ TRY (
    simp[IO_fs_component_equality]
    \\ match_mp_tac (GSYM ALIST_FUPDKEY_unchanged)
    \\ simp[MAX_DEF] )
  \\ rw[] \\ fs[forwardFD_def,libTheory.the_def]
  \\ pairarg_tac \\ fs[]);

Theorem linesFD_cons_imp
  `linesFD fs fd = ln::ls ⇒
   lineFD fs fd = SOME ln ∧
   linesFD (lineForwardFD fs fd) fd = ls`
  (simp[linesFD_def,lineForwardFD_def]
  \\ CASE_TAC \\ CASE_TAC
  \\ strip_tac
  \\ rename1`_ = SOME (content,off)`
  \\ conj_asm1_tac
  >- (
    simp[lineFD_def]
    \\ Cases_on`DROP off content` \\ rfs[DROP_NIL]
    \\ conj_asm1_tac
    >- ( CCONTR_TAC \\ fs[DROP_LENGTH_TOO_LONG] )
    \\ fs[splitlines_def,FIELDS_def]
    \\ pairarg_tac \\ fs[]
    \\ every_case_tac \\ fs[] \\ rw[]
    \\ fs[NULL_EQ]
    \\ imp_res_tac SPLITP_NIL_IMP \\ fs[] \\ rw[]
    >- ( Cases_on`FIELDS ($= #"\n") t` \\ fs[] )
    >- ( Cases_on`FIELDS ($= #"\n") (TL r)` \\ fs[] ))
  \\ reverse IF_CASES_TAC \\ fs[DROP_LENGTH_TOO_LONG]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`splitlines (DROP off content)` \\ fs[] \\ rveq
  \\ AP_TERM_TAC
  \\ imp_res_tac splitlines_next
  \\ fs[DROP_DROP_T,ADD1,NULL_EQ]
  \\ imp_res_tac splitlines_CONS_FST_SPLITP \\ rfs[]
  \\ IF_CASES_TAC \\ fs[] \\ rw[]
  \\ fs[SPLITP_NIL_SND_EVERY]
  \\ rveq \\ fs[DROP_LENGTH_TOO_LONG]);

Theorem linesFD_lineForwardFD
  `linesFD (lineForwardFD fs fd) fd' =
   if fd = fd' then
     DROP 1 (linesFD fs fd)
   else linesFD fs fd'`
  (rw[linesFD_def,lineForwardFD_def]
  >- (
    CASE_TAC \\ fs[]
    \\ CASE_TAC \\ fs[]
    \\ CASE_TAC \\ fs[DROP_LENGTH_TOO_LONG]
    \\ pairarg_tac \\ fs[]
    \\ qmatch_asmsub_rename_tac`DROP x pos`
    \\ Cases_on`splitlines (DROP x pos)` \\ fs[DROP_NIL]
    \\ imp_res_tac splitlines_CONS_FST_SPLITP
    \\ imp_res_tac splitlines_next
    \\ rveq
    \\ rw[NULL_EQ,DROP_DROP_T,ADD1]
    \\ fs[SPLITP_NIL_SND_EVERY] \\ rw[]
    \\ fs[o_DEF]
    \\ drule SPLITP_EVERY
    \\ strip_tac \\ fs[DROP_LENGTH_TOO_LONG])
  \\ CASE_TAC \\ fs[]
  \\ CASE_TAC \\ fs[]
  \\ CASE_TAC \\ fs[]
  \\ pairarg_tac \\ fs[]
  \\ simp[get_file_content_def]
  \\ simp[forwardFD_def,ALIST_FUPDKEY_ALOOKUP]
  \\ CASE_TAC \\ fs[]);

Theorem lineForwardFD_forwardFD
  `∀fs fd. ∃n. lineForwardFD fs fd = forwardFD fs fd n`
  (rw[forwardFD_def,lineForwardFD_def]
  \\ CASE_TAC
  >- (
    qexists_tac`0`
    \\ simp[IO_fs_component_equality]
    \\ match_mp_tac (GSYM ALIST_FUPDKEY_unchanged)
    \\ simp[FORALL_PROD] )
  \\ CASE_TAC
  \\ pairarg_tac \\ fs[]
  \\ rw[]
  >- metis_tac[]
  >- metis_tac[]
  >- (
    qexists_tac`0`
    \\ simp[IO_fs_component_equality]
    \\ match_mp_tac (GSYM ALIST_FUPDKEY_unchanged)
    \\ simp[FORALL_PROD] ));

Theorem get_file_content_lineForwardFD_forwardFD
  `∀fs fd. get_file_content fs fd = SOME (x,pos) ⇒
     lineForwardFD fs fd = forwardFD fs fd (LENGTH(FST(SPLITP((=)#"\n")(DROP pos x))) +
                                            if NULL(SND(SPLITP((=)#"\n")(DROP pos x))) then 0 else 1)`
  (simp[forwardFD_def,lineForwardFD_def]
  \\ ntac 3 strip_tac
  \\ pairarg_tac \\ fs[]
  \\ reverse IF_CASES_TAC \\ fs[DROP_LENGTH_TOO_LONG,SPLITP]
  \\ rw[IO_fs_component_equality]
  \\ match_mp_tac (GSYM ALIST_FUPDKEY_unchanged)
  \\ simp[FORALL_PROD] );

(* Property ensuring that standard streams are correctly opened *)
val STD_streams_def = Define
  `STD_streams fs = ?inp out err.
    (ALOOKUP fs.files (IOStream(strlit "stdout")) = SOME out) ∧
    (ALOOKUP fs.files (IOStream(strlit "stderr")) = SOME err) ∧
    (∀fd md off. ALOOKUP fs.infds fd = SOME (IOStream(strlit "stdin"),md,off) ⇔ fd = 0 ∧ md = ReadMode ∧ off = inp) ∧
    (∀fd md off. ALOOKUP fs.infds fd = SOME (IOStream(strlit "stdout"),md,off) ⇔ fd = 1 ∧ md = WriteMode ∧ off = LENGTH out) ∧
    (∀fd md off. ALOOKUP fs.infds fd = SOME (IOStream(strlit "stderr"),md,off) ⇔ fd = 2 ∧ md = WriteMode ∧ off = LENGTH err)`;

Theorem STD_streams_fsupdate
  `! fs fd k pos c.
   ((fd = 1 \/ fd = 2) ==> LENGTH c = pos) /\
   (*
   (fd >= 3 ==> (FST(THE (ALOOKUP fs.infds fd)) <> IOStream(strlit "stdout") /\
                 FST(THE (ALOOKUP fs.infds fd)) <> IOStream(strlit "stderr"))) /\
   *)
    STD_streams fs ==>
    STD_streams (fsupdate fs fd k pos c)`
  (rw[STD_streams_def,fsupdate_def]
  \\ CASE_TAC \\ fs[] >- metis_tac[]
  \\ CASE_TAC \\ fs[ALIST_FUPDKEY_ALOOKUP]
  \\ qmatch_goalsub_abbrev_tac`out' = SOME _ ∧ (err' = SOME _ ∧ _)`
  \\ qmatch_assum_rename_tac`_ = SOME (fnm,_)`
  \\ map_every qexists_tac[`if fnm = IOStream(strlit"stdin") then pos else inp`,`THE out'`,`THE err'`]
  \\ conj_tac >- rw[Abbr`out'`]
  \\ conj_tac >- rw[Abbr`err'`]
  \\ unabbrev_all_tac
  \\ rw[] \\ fs[] \\ rw[] \\ TOP_CASE_TAC \\ fs[] \\ rw[] \\ rfs[]
  \\ rw[] \\ rfs[PAIR_MAP]
  \\ metis_tac[NOT_SOME_NONE,SOME_11,PAIR,FST]);

Theorem STD_streams_openFileFS
  `!fs s k. STD_streams fs ==> STD_streams (openFileFS s fs md k)`
   (rw[STD_streams_def,openFileFS_files] >>
   map_every qexists_tac[`inp`,`out`,`err`] >>
   fs[openFileFS_def] >> rpt(CASE_TAC >> fs[]) >>
   fs[openFile_def,IO_fs_component_equality] >>
   qpat_x_assum`_::_ = _`(assume_tac o SYM) \\ fs[] \\
   rw[] \\ metis_tac[ALOOKUP_MEM,nextFD_NOT_MEM,PAIR]);

Theorem STD_streams_numchars
 `!fs ll. STD_streams fs = STD_streams (fs with numchars := ll)`
 (fs[STD_streams_def]);

val lemma = Q.prove(
  `IOStream (strlit "stdin") ≠ IOStream (strlit "stdout") ∧
   IOStream (strlit "stdin") ≠ IOStream (strlit "stderr") ∧
   IOStream (strlit "stdout") ≠ IOStream (strlit "stderr")`,rw[]);

Theorem STD_streams_forwardFD
  `fd ≠ 1 ∧ fd ≠ 2 ⇒
   (STD_streams (forwardFD fs fd n) = STD_streams fs)`
  (rw[STD_streams_def,forwardFD_def,ALIST_FUPDKEY_ALOOKUP]
  \\ Cases_on`fd = 0`
  >- (
    EQ_TAC \\ rw[]
    \\ fsrw_tac[ETA_ss][option_case_eq,PULL_EXISTS,PAIR_MAP]
    >- (
      qexists_tac`inp-n` \\ rw[]
      >- (
        Cases_on`fd = 0` \\ fs[]
        >- (
          last_x_assum(qspecl_then[`fd`,`ReadMode`,`inp`]mp_tac)
          \\ rw[] \\ rw[] \\ PairCases_on`v` \\ fs[]
          \\ metis_tac[])
        \\ last_x_assum(qspecl_then[`fd`,`md`,`off`]mp_tac)
        \\ rw[] )
      \\ metis_tac[SOME_11, lemma, PAIR, FST, SND, DECIDE``1n ≠ 0 ∧ 2 ≠ 0n``])
    \\ qexists_tac`inp+n` \\ rw[]
    \\ metis_tac[PAIR,SOME_11,FST,SND,lemma,ADD_COMM] )
  \\ EQ_TAC \\ rw[]
  \\ fsrw_tac[ETA_ss][option_case_eq,PULL_EXISTS,PAIR_MAP]
  \\ qexists_tac`inp` \\ rw[]
  \\ metis_tac[PAIR,SOME_11,FST,SND,lemma]);

Theorem STD_streams_bumpFD
  `fd ≠ 1 ∧ fd ≠ 2 ⇒
   (STD_streams (bumpFD fd fs n) = STD_streams fs)`
  (rw[bumpFD_forwardFD,GSYM STD_streams_numchars,STD_streams_forwardFD]);

Theorem STD_streams_nextFD
  `STD_streams fs ⇒ 3 ≤ nextFD fs`
  (rw[STD_streams_def,nextFD_def,MEM_MAP,EXISTS_PROD]
  \\ numLib.LEAST_ELIM_TAC \\ rw[]
  >- (
    CCONTR_TAC \\ fs[]
    \\ `CARD (count (LENGTH fs.infds + 1)) ≤ CARD (set (MAP FST fs.infds))`
    by (
      match_mp_tac (MP_CANON CARD_SUBSET)
      \\ simp[SUBSET_DEF,MEM_MAP,EXISTS_PROD] )
    \\ `CARD (set (MAP FST fs.infds)) ≤ LENGTH fs.infds` by metis_tac[CARD_LIST_TO_SET,LENGTH_MAP]
    \\ fs[] )
  \\ Cases_on`n=0` >- metis_tac[ALOOKUP_MEM]
  \\ Cases_on`n=1` >- metis_tac[ALOOKUP_MEM]
  \\ Cases_on`n=2` >- metis_tac[ALOOKUP_MEM]
  \\ decide_tac);

Theorem STD_streams_lineForwardFD
  `fd ≠ 1 ∧ fd ≠ 2 ⇒
   (STD_streams (lineForwardFD fs fd) ⇔ STD_streams fs)`
  (rw[lineForwardFD_def]
  \\ CASE_TAC \\ fs[]
  \\ CASE_TAC \\ fs[]
  \\ pairarg_tac \\ fs[]
  \\ IF_CASES_TAC \\ fs[]
  \\ simp[STD_streams_forwardFD]);

Theorem STD_streams_fastForwardFD
  `fd ≠ 1 ∧ fd ≠ 2 ⇒
   (STD_streams (fastForwardFD fs fd) ⇔ STD_streams fs)`
  (rw[fastForwardFD_def]
  \\ Cases_on`ALOOKUP fs.infds fd` \\ fs[libTheory.the_def]
  \\ pairarg_tac \\ fs[]
  \\ Cases_on`ALOOKUP fs.files fnm` \\ fs[libTheory.the_def]
  \\ EQ_TAC \\ rw[STD_streams_def,option_case_eq,ALIST_FUPDKEY_ALOOKUP,PAIR_MAP] \\ rw[]
  >- (
    qmatch_assum_rename_tac`ALOOKUP _ fnm = SOME r` \\
    qexists_tac`if fd = 0 then off else inp` \\ rw[] \\
    metis_tac[SOME_11,PAIR,FST,SND,lemma] ) \\
  qmatch_assum_rename_tac`ALOOKUP _ fnm = SOME r` \\
  qexists_tac`if fd = 0 then MAX (LENGTH r) off else inp` \\ rw[EXISTS_PROD] \\
  metis_tac[SOME_11,PAIR,FST,SND,lemma] );

val get_mode_def = Define`
  get_mode fs fd =
    OPTION_MAP (FST o SND) (ALOOKUP fs.infds fd)`;

Theorem get_mode_with_numchars
  `get_mode (fs with numchars := ll) fd = get_mode fs fd`
  (rw[get_mode_def]);

Theorem get_mode_with_files
  `get_mode (fs with files := n) fd = get_mode fs fd`
  (rw[get_mode_def]);

Theorem get_mode_forwardFD[simp]
  `get_mode (forwardFD fs fd n) fd' = get_mode fs fd'`
  (rw[get_mode_def,forwardFD_def,ALIST_FUPDKEY_ALOOKUP]
  \\ TOP_CASE_TAC \\ rw[]);

Theorem get_mode_lineForwardFD[simp]
  `get_mode (lineForwardFD fs fd) fd' = get_mode fs fd'`
  (qspecl_then[`fs`,`fd`]strip_assume_tac lineForwardFD_forwardFD
  \\ rw[]);

Theorem STD_streams_get_mode
  `STD_streams fs ⇒
   (get_mode fs 0 = SOME ReadMode) ∧
   (get_mode fs 1 = SOME WriteMode) ∧
   (get_mode fs 2 = SOME WriteMode)`
  (rw[STD_streams_def, get_mode_def, EXISTS_PROD]
  \\ metis_tac[]);

val _ = export_theory();
