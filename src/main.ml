(*
 * Copyright (c) 2010-2012,
 *  Jinseong Jeon <jsjeon@cs.umd.edu>
 *  Kris Micinski <micinski@cs.umd.edu>
 *  Jeff Foster   <jfoster@cs.umd.edu>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. The names of the contributors may not be used to endorse or promote
 * products derived from this software without specific prior written
 * permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

(***********************************************************************)
(* Main                                                                *)
(***********************************************************************)

module St = Stats

module U = Util

module J  = Java
module D  = Dex
module P  = Parse

module Up  = Unparse
module Hup = Htmlunparse

module Cg = Callgraph
module Ct = Ctrlflow
module Lv = Liveness
module Cp = Propagation

module Md  = Modify
module Lgg = Logging

module Cm  = Combine
module Dp  = Dump

module A = Arg
module L = List
module S = String

(***********************************************************************)
(* Basic Elements/Functions                                            *)
(***********************************************************************)

let dex = ref "classes.dex"

let dump (tx: D.dex) : unit =
  St.time "dump" (Dp.dump !dex) tx

let dump_hello _ : unit =
  St.time "dump_hello" (Dp.dump !dex) (Md.hello ())

let infile = ref "-"
let outputdir = ref "output"

let dump_html (tx : D.dex) : unit =
  St.time "dump_html" (Hup.generate_documentation tx !outputdir) !infile

let lib = ref "tutorial/logging/bin/classes.dex"

let combine (tx: D.dex) : unit =
 try (
    let chan' = open_in_bin !lib in
    let libdx = St.time "parse" P.parse chan' in
    close_in chan';
    St.time "dump" (Dp.dump !dex) (St.time "merge" (Cm.combine libdx) tx)
  )
  with End_of_file -> prerr_endline "EOF"

let cls = ref ""
let mtd = ref ""

let get_citm (tx: D.dex) : D.code_item =
  let cid = D.get_cid tx (J.to_java_ty !cls) in
  let mid, _ = D.get_the_mtd tx cid !mtd in
  let _, citm = D.get_citm tx cid mid in citm

let dump_method (tx: D.dex) : unit =
  let citm = get_citm tx in
  St.time "dump_method" Up.print_method tx citm

let cg (tx: D.dex) : unit =
  let g = St.time "callgraph" Cg.make_cg tx in
  St.time "callgraph" (Cg.cg2dot tx) g

let get_cfg (tx: D.dex) : Ct.cfg =
  let citm = get_citm tx in
  St.time "cfg" (Ct.make_cfg tx) citm

let cfg (tx: D.dex) : unit =
  let cfg = get_cfg tx in
  St.time "cfg" (Ct.cfg2dot tx) cfg

let dom (tx: D.dex) : unit =
  let cfg = get_cfg tx in
  let dom = St.time "dom" Ct.doms cfg in
  St.time "dom" (Ct.dom2dot tx cfg) dom

let pdom (tx: D.dex) : unit =
  let cfg = get_cfg tx in
  let pdom = St.time "pdom" Ct.pdoms cfg in
  St.time "pdom" (Ct.pdom2dot tx cfg) pdom

(***********************************************************************)
(* Analyses                                                            *)
(***********************************************************************)

let dependants (tx: D.dex) : unit =
  let g = St.time "callgraph" Cg.make_cg tx in
  let cid = D.get_cid tx (J.to_java_ty !cls) in
  let cids = St.time "dependants" (Cg.dependants tx g) cid in
    L.iter (fun id -> Log.i (D.get_ty_str tx id)) cids

let do_dfa (tag: string) (tx: D.dex) : unit =
  Log.set_level "verbose";
  let citm = get_citm tx in
  let dfa = match tag with
    | "live"  -> St.time tag (Lv.make_dfa tx) citm
    | "const" -> St.time tag (Cp.make_dfa tx) citm
  in
  let module DFA = (val dfa: Dataflow.ANALYSIS with type st = D.link) in
  St.time tag DFA.fixed_pt ()

(***********************************************************************)
(* Logging                                                             *)
(***********************************************************************)

let instrument_logging (tx: D.dex) : unit =
  let logging_library = "./tutorial/logging/bin/classes.dex" in
  (* parse logging library *)
  let chan = open_in_bin !lib in
  let liblog = P.parse chan in
  close_in chan;
  (* merge the external dex file *)
  let cx = St.time "merge" (Cm.combine liblog) tx in
  (* seed new addresses for modification *)
  Md.seed_addr cx.D.header.D.file_size;
  (* modify target dex accordingly *)
  Lgg.modify tx;
  (* finally, dump the rewritten dex *)
  St.time "dump" (Dp.dump !dex) cx

(***********************************************************************)
(* Arguments                                                           *)
(***********************************************************************)

let task = ref None

let do_unparse       () = task := Some (St.time "unparse" Up.unparse)
let do_info          () = task := Some (St.time "info."   Up.print_info)
let do_classes       () = task := Some (St.time "class"   Up.print_classes)

let do_dump          () = task := Some dump
let do_hello         () = task := Some dump_hello

let do_htmlunparse   () = task := Some dump_html

let do_combine       () = task := Some combine

let do_dumpmethod    () = task := Some dump_method
let do_cg            () = task := Some cg
let do_cfg           () = task := Some cfg
let do_dom           () = task := Some dom
let do_pdom          () = task := Some pdom

let do_dependants    () = task := Some dependants
let do_live          () = task := Some (do_dfa "live")
let do_const         () = task := Some (do_dfa "const")

let do_logging       () = task := Some instrument_logging

let arg_specs = A.align
  [
    ("-log", A.String Log.set_level, " set logging level");
    ("-unparse", A.Unit do_unparse, " print dex in yaml format");
    ("-info",    A.Unit do_info,    " print info about dex file");
    ("-classes", A.Unit do_classes, " print class names in dex file");
    ("-out",   A.Set_string dex, " output file name (default: "^(!dex)^")");
    ("-dump",  A.Unit do_dump,   " dump dex binary");
    ("-hello", A.Unit do_hello,  " API test");
    ("-outputdir",   A.Set_string outputdir,
     " directory in which to place generated htmls (default: "^(!outputdir)^")");
    ("-htmlunparse", A.Unit do_htmlunparse, " format dex in an html document");
    ("-lib",     A.Set_string lib,  " library dex name (default: "^(!lib)^")");
    ("-combine", A.Unit do_combine, " combine two dex files");
    ("-cls",  A.Set_string cls, " target class name");
    ("-mtd",  A.Set_string mtd, " target method name");
    ("-dump_method", A.Unit do_dumpmethod, 
     " dump instructions for a specified method");
    ("-cg",   A.Unit do_cg,     " call graph in dot format");
    ("-cfg",  A.Unit do_cfg,    " control-flow graph in dot format");
    ("-dom",  A.Unit do_dom,    " dominator tree in dot format");
    ("-pdom", A.Unit do_pdom,   " post dominator tree in dot format");
    ("-dependants", A.Unit do_dependants, " find dependent classes");
    ("-live",       A.Unit do_live,       " liveness analysis");
    ("-const",      A.Unit do_const,      " constant propagation");
    ("-logging", A.Unit do_logging,
     " instrument logging feature into the given dex");
  ]

(***********************************************************************)
(* Main                                                                *)
(***********************************************************************)

let usage = "Usage: " ^ Sys.argv.(0) ^ " [opts] [dex]\n"

let main () =
  A.parse arg_specs (fun s -> infile := s) usage;
  let ch, k =
    if (!infile = "-") then
      stdin, fun () -> ()
    else
      let chan = open_in_bin !infile in
      chan,  fun () -> close_in chan
  in
  if (!infile <> "-") then
  (
    let f_sz = 100 * in_channel_length ch
    and ctrl = Gc.get () in
    ctrl.Gc.minor_heap_size <- max f_sz ctrl.Gc.minor_heap_size;
    Gc.set ctrl
  );
  try (
    match !task with
    | Some f ->
    (
      St.reset St.HardwareIfAvail;
      if f == dump_hello then f (D.empty_dex ()) else
      (
        let dex = St.time "parse" P.parse ch in
        k ();
        f dex
      );
      St.print stderr "====== redexer performance statistics ======\n"
    )
    | _ -> A.usage arg_specs usage
  )
  with End_of_file -> prerr_endline "EOF"
;;

main ();;
