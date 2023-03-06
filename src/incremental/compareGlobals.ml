open GoblintCil
open MyCFG
open CilMaps
include CompareAST
include CompareCFG

module GlobalMap = Map.Make(String)

type global_def = Var of varinfo | Fun of fundec
type global_col = {decls: varinfo option; def: global_def option}

let name_of_global g = match g with
  | GVar (v,_,_) -> v.vname
  | GFun (f,_) -> f.svar.vname
  | GVarDecl (v,_) -> v.vname
  | _ -> failwith "global constructor not supported"

type nodes_diff = {
  unchangedNodes: (node * node) list;
  primObsoleteNodes: node list; (** primary obsolete nodes -> all obsolete nodes are reachable from these *)
}

type unchanged_global = {
  old: global_col;
  current: global_col
}
(** For semantically unchanged globals, still keep old and current version of global for resetting current to old. *)

type changed_global = {
  old: global_col;
  current: global_col;
  unchangedHeader: bool;
  diff: nodes_diff option
}

module VarinfoSet = Set.Make(CilType.Varinfo)

type change_info = {
  mutable changed: changed_global list;
  mutable unchanged: unchanged_global list;
  mutable removed: global_col list;
  mutable added: global_col list;
  mutable exclude_from_rel_destab: VarinfoSet.t;
  (** Set of functions that are to be force-reanalyzed.
      These functions are additionally included in the [changed] field, among the other changed globals. *)
}

let empty_change_info () : change_info =
  {added = []; removed = []; changed = []; unchanged = []; exclude_from_rel_destab = VarinfoSet.empty}

(* 'ChangedFunHeader' is used for functions whose varinfo or formal parameters changed. 'Changed' is used only for
 * changed functions whose header is unchanged and changed non-function globals *)
type change_status = Unchanged | Changed | ChangedFunHeader of Cil.fundec | ForceReanalyze of Cil.fundec

(** Given a boolean that indicates whether the code object is identical to the previous version, returns the corresponding [change_status]*)
let unchanged_to_change_status = function
  | true -> Unchanged
  | false -> Changed

let empty_rename_mapping: rename_mapping = (StringMap.empty, VarinfoMap.empty, VarinfoMap.empty, ([], []))

let should_reanalyze (fdec: Cil.fundec) =
  List.mem fdec.svar.vname (GobConfig.get_string_list "incremental.force-reanalyze.funs")

(* If some CFGs of the two functions to be compared are provided, a fine-grained CFG comparison is done that also determines which
 * nodes of the function changed. If on the other hand no CFGs are provided, the "old" AST comparison on the CIL.file is
 * used for functions. Then no information is collected regarding which parts/nodes of the function changed. *)
let eqF (old: Cil.fundec) (current: Cil.fundec) (cfgs : (cfg * (cfg * cfg)) option) (global_function_rename_mapping: method_rename_assumptions) (global_var_rename_mapping: glob_var_rename_assumptions) =
  let identical, diffOpt, (_, renamed_method_dependencies, renamed_global_vars_dependencies, renamesOnSuccess) =
    if should_reanalyze current then
      ForceReanalyze current, None, empty_rename_mapping
    else

      (* Compares the two varinfo lists, returning as a first element, if the size of the two lists are equal,
       * and as a second a rename_mapping, holding the rename assumptions *)
      let rec rename_mapping_aware_compare (alocals: varinfo list) (blocals: varinfo list) (rename_mapping: string StringMap.t) = match alocals, blocals with
        | [], [] -> true, rename_mapping
        | origLocal :: als, nowLocal :: bls ->
          let new_mapping = StringMap.add origLocal.vname nowLocal.vname rename_mapping in

          (*TODO: maybe optimize this with eq_varinfo*)
          rename_mapping_aware_compare als bls new_mapping
        | _, _ -> false, rename_mapping
      in

      let unchangedHeader, headerRenameMapping, renamesOnSuccessHeader = match cfgs with
        | None -> (
            let headerSizeEqual, headerRenameMapping = rename_mapping_aware_compare old.sformals current.sformals (StringMap.empty) in
            let actHeaderRenameMapping = (headerRenameMapping, global_function_rename_mapping, global_var_rename_mapping, ([], [])) in

            let (unchangedHeader, (_, _, _, renamesOnSuccessHeader)) =
              eq_varinfo old.svar current.svar ~rename_mapping:actHeaderRenameMapping
              &&>> forward_list_equal eq_varinfo old.sformals current.sformals in
            unchangedHeader, headerRenameMapping, renamesOnSuccessHeader
          )
        | Some _ -> (
            let unchangedHeader, headerRenameMapping = eq_varinfo old.svar current.svar ~rename_mapping:empty_rename_mapping &&>>
                                                       forward_list_equal eq_varinfo old.sformals current.sformals in
            let (_, _, _, renamesOnSuccessHeader) = headerRenameMapping in

            (unchangedHeader && is_rename_mapping_empty headerRenameMapping), StringMap.empty, renamesOnSuccessHeader
          )
      in

      if not unchangedHeader then ChangedFunHeader current, None, empty_rename_mapping
      else
        (* Here the local variables are checked to be equal *)
        (* sameLocals: when running on cfg, true iff the locals are identical; on ast: if the size of the locals stayed the same*)
        let sameLocals, rename_mapping =
          match cfgs with
          | None -> (
              let sizeEqual, local_rename = rename_mapping_aware_compare old.slocals current.slocals headerRenameMapping in
              sizeEqual, (local_rename, global_function_rename_mapping, global_var_rename_mapping, renamesOnSuccessHeader)
            )
          | Some _ -> (
              let isEqual, rename_mapping = forward_list_equal eq_varinfo old.slocals current.slocals ~rename_mapping:(StringMap.empty, VarinfoMap.empty, VarinfoMap.empty, renamesOnSuccessHeader) in
              isEqual && is_rename_mapping_empty rename_mapping, rename_mapping
            )
        in

        if sameLocals then
          (Changed, None, empty_rename_mapping)
        else
          match cfgs with
          | None ->
            let (identical, new_rename_mapping) = eq_block (old.sbody, old) (current.sbody, current) ~rename_mapping in
            unchanged_to_change_status identical, None, new_rename_mapping
          | Some (cfgOld, (cfgNew, cfgNewBack)) ->
            let module CfgOld : MyCFG.CfgForward = struct let next = cfgOld end in
            let module CfgNew : MyCFG.CfgBidir = struct let prev = cfgNewBack let next = cfgNew end in
            let matches, diffNodes1, updated_rename_mapping = compareFun (module CfgOld) (module CfgNew) old current rename_mapping in
            if diffNodes1 = [] then (Unchanged, None, updated_rename_mapping)
            else (Changed, Some {unchangedNodes = matches; primObsoleteNodes = diffNodes1}, updated_rename_mapping)
  in
  identical, diffOpt, renamed_method_dependencies, renamed_global_vars_dependencies, renamesOnSuccess
