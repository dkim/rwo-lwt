(*
 * Concurrent Programming with Lwt
 *
 * Written in 2017 by Deokhwan Kim
 *
 * To the extent possible under law, the author(s) have dedicated all copyright
 * and related and neighboring rights to this software to the public domain
 * worldwide. This software is distributed without any warranty.
 *
 * You should have received a copy of the CC0 Public Domain Dedication along
 * with this software. If not, see
 * <http://creativecommons.org/publicdomain/zero/1.0/>.
 *)


(* Async Basics *)

let file_contents (filename : Lwt_io.file_name) : string Lwt.t =
  Lwt_io.with_file ~mode:Lwt_io.input filename
    (fun channel -> Lwt_io.read channel)

let save (filename : Lwt_io.file_name) ~(contents : string) : unit Lwt.t =
  Lwt_io.with_file ~mode:Lwt_io.output filename
    (fun channel -> Lwt_io.write channel contents)

let uppercase_file (filename : Lwt_io.file_name) : unit Lwt.t =
  let%lwt text = file_contents filename in
  save filename ~contents:(String.uppercase_ascii text)

let count_lines (filename : Lwt_io.file_name) : int Lwt.t =
  let%lwt text = file_contents filename in
  String.split_on_char '\n' text |> List.length |> Lwt.return


(* Ivars and Upon *)

module type Delayer_intf = sig
  type t
  val create : float -> t
  val schedule : t -> (unit -> 'a Lwt.t) -> 'a Lwt.t
end

module Delayer : Delayer_intf = struct
  type t = {delay: float; jobs: (unit -> unit) Queue.t}

  let create (delay : float) : t = {delay; jobs = Queue.create ()}

  let schedule (t : t) (thunk : unit -> 'a Lwt.t) : 'a Lwt.t =
    let waiter, wakener = Lwt.wait () in
    Queue.add
      (fun () ->
         Lwt.on_any (thunk ()) (Lwt.wakeup wakener) (Lwt.wakeup_exn wakener))
      t.jobs;
    Lwt.on_termination (Lwt_unix.sleep t.delay) (Queue.take t.jobs);
    waiter
end


(* Example: An Echo Server *)

let rec copy_blocks (buffer : bytes) (r : Lwt_io.input_channel) (w : Lwt_io.output_channel) : unit Lwt.t =
  match%lwt Lwt_io.read_into r buffer 0 (Bytes.length buffer) with
  | 0 -> Lwt.return_unit
  | bytes_read ->
    Lwt_io.write_from_exactly w buffer 0 bytes_read >> copy_blocks buffer r w

(*
let run () : unit =
  ((let%lwt server =
      Lwt_io.establish_server (Lwt_unix.ADDR_INET (Unix.inet_addr_any, 8765))
        (fun (r, w) ->
           let buffer = Bytes.create (16 * 1024) in
           copy_blocks buffer r w)
    in
    Lwt.return server) : Lwt_io.server Lwt.t) |> ignore
*)

let never_terminate : 'a . 'a Lwt.t = fst (Lwt.wait ())

(*
let () =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  run ();
  Lwt_main.run never_terminate
*)


(* Improving the Echo Server *)

let run (uppercase : bool) (port : int) : unit Lwt.t =
  let%lwt server =
    Lwt_io.establish_server (Lwt_unix.ADDR_INET (Unix.inet_addr_any, port))
      (fun (r, w) ->
         Lwt_io.read_chars r
         |> (if uppercase then Lwt_stream.map Char.uppercase_ascii
             else fun x -> x)
         |> Lwt_io.write_chars w)
  in
  (server : Lwt_io.server) |> ignore;
  never_terminate

(*
let run (uppercase : bool) (port : int) : unit Lwt.t =
  let%lwt server =
    Lwt_io.establish_server (Lwt_unix.ADDR_INET (Unix.inet_addr_any, port))
      (fun (r, w) ->
         let reader = Lwt_pipe.IO.read r in
         let writer =
           Lwt_pipe.IO.write w
           |> (if uppercase then Lwt_pipe.Writer.map ~f:String.uppercase_ascii
               else fun x -> x)
         in
         Lwt_pipe.connect ~ownership:`OutOwnsIn reader writer;
         Lwt_pipe.wait writer)
  in
  (server : Lwt_io.server) |> ignore;
  never_terminate
*)

let () =
  let uppercase = ref false
  and port = ref 8765 in
  let options = [
    "-uppercase", Arg.Set uppercase, "Convert to uppercase before echoing back";
    "-port", Arg.Set_int port, "Port to listen on (default 8765)";
  ] in
  let usage = "Usage: " ^ Sys.argv.(0) ^ " [-uppercase] [-port num]" in
  Arg.parse
    options
    (fun arg -> raise (Arg.Bad (Printf.sprintf "invalid argument -- '%s'" arg)))
    usage;

  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (run !uppercase !port)


(* Example: Searching Definitions with DuckDuckGo *)
