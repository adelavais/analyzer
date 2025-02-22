(* functions for driving specParser *)

open Batteries

(* config *)
let save_dot = true

let line = ref 1
exception Parse_error of string

let parse ?repl:(repl=false) ?print:(print=false) ?dot:(dot=false) cin =
  let lexbuf = Lexing.from_channel cin in
  let defs = ref [] in
  (* Printf.printf "\nrepl: %B, print: %B, dot: %B, save_dot: %B\n" repl print dot save_dot; *)
  try
    while true do (* loop over all lines *)
      try
        let result = SpecParser.file SpecLexer.token lexbuf in
        defs := !defs@[result];
        incr line;
        if print then (print_endline (SpecCore.def_to_string result); flush stdout)
      with
      (* just an empty line -> don't print *)
      | SpecCore.Endl  -> incr line
      (* somehow gets raised in some cases instead of SpecCore.Eof *)
      | BatInnerIO.Input_closed -> raise SpecCore.Eof
      (* catch and print in repl-mode *)
      | e when repl -> print_endline (Printexc.to_string e)
    done;
    ([], []) (* never happens, but ocaml needs it for type *)
  with
  (* done *)
  | SpecCore.Eof   ->
    let nodes = List.filter_map (function SpecCore.Node x -> Some x | _ -> None) !defs in
    let edges = List.filter_map (function SpecCore.Edge x -> Some x | _ -> None) !defs in
    if print then Printf.printf "\n#Definitions: %i, #Nodes: %i, #Edges: %i\n"
        (List.length !defs) (List.length nodes) (List.length edges);
    if save_dot && not dot then (
      let dotgraph = SpecCore.to_dot_graph !defs in
      output_file ~filename:"result/graph.dot" ~text:dotgraph;
      print_endline ("saved graph as "^Sys.getcwd ()^"/result/graph.dot");
    );
    if dot then (
      print_endline (SpecCore.to_dot_graph !defs)
    );
    (nodes, edges)
  (* stop on parsing error if not in REPL and include line number *)
  | e -> raise (Parse_error ("Line "^string_of_int !line^": "^Printexc.to_string e))

let parseFile filename = parse (open_in filename)

(* print ~first:"[" ~sep:", " ~last:"]" print_any stdout @@ 5--10 *)
