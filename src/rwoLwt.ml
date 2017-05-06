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

(*
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
*)


(* Example: Searching Definitions with DuckDuckGo *)

(* URI Handling *)

(*
let query_uri : string -> Uri.t =
  let base_uri = Uri.of_string "https://api.duckduckgo.com/?format=json" in
  (fun query -> Uri.add_query_param base_uri ("q", [query]))
*)


(* Parsing JSON Strings *)

let get_definition_from_json (json : string) : string option =
  match Yojson.Safe.from_string json with
  | `Assoc kv_list ->
    let find key =
      try
        match List.assoc key kv_list with
        | `String "" -> None
        | s -> Some (Yojson.Safe.to_string s)
      with Not_found -> None
    in
    begin match find "Abstract" with
    | Some _ as x -> x
    | None -> find "Definition"
    end
  | _ -> None


(* Executing an HTTP Client Query *)

(*
let get_definition (word : string) : (string * string option) Lwt.t =
  let%lwt _resp, body = Cohttp_lwt_unix.Client.get (query_uri word) in
  let%lwt body' = Cohttp_lwt_body.to_string body in
  Lwt.return (word, get_definition_from_json body')

let print_result ((word, definition) : string * string option) : unit Lwt.t =
  Lwt_io.printf "%s\n%s\n\n%s\n\n"
    word
    (String.init (String.length word) (fun _ -> '-'))
    (match definition with
     | None -> "No definition found"
     | Some def ->
       Format.pp_set_margin Format.str_formatter 70;
       Format.pp_print_text Format.str_formatter def;
       Format.flush_str_formatter ())

let search_and_print (words : string list) : unit Lwt.t =
  let%lwt results = Lwt_list.map_p get_definition words in
  Lwt_list.iter_s print_result results

(*
let search_and_print (words : string list) : unit Lwt.t =
  Lwt_list.iter_p
    (fun word ->
       let%lwt result = get_definition word in
       print_result result)
    words
*)

let () =
  let words = ref [] in
  let usage = "Usage: " ^ Sys.argv.(0) ^ " [word ...]" in
  Arg.parse [] (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print !words)
*)


(* Example: Handling Exceptions with DuckDuckGo *)

let query_uri ~(server : string) (query : string) : Uri.t =
  let base_uri =
    Uri.of_string (String.concat "" ["https://"; server; "/?format=json"])
  in
  Uri.add_query_param base_uri ("q", [query])

(*
let get_definition ~(server : string) (word : string) : (string * (string option, string) result) Lwt.t =
  try%lwt
    let%lwt _resp, body = Cohttp_lwt_unix.Client.get (query_uri ~server word) in
    let%lwt body' = Cohttp_lwt_body.to_string body in
    Lwt.return (word, Ok (get_definition_from_json body'))
  with _ -> Lwt.return (word, Error "Unexpected failure")
*)

let print_result ((word, definition) : string * (string option, string) result) : unit Lwt.t =
  Lwt_io.printf "%s\n%s\n\n%s\n\n"
    word
    (String.init (String.length word) (fun _ -> '-'))
    (match definition with
     | Error s -> "DuckDuckGo query failed: " ^ s
     | Ok None -> "No definition found"
     | Ok (Some def) ->
       Format.pp_set_margin Format.str_formatter 70;
       Format.pp_print_text Format.str_formatter def;
       Format.flush_str_formatter ())

(*
let search_and_print ~(servers : string list) (words : string list) : unit Lwt.t =
  let servers = Array.of_list servers in
  let%lwt results =
    Lwt_list.mapi_p
      (fun i word ->
         let server = servers.(i mod Array.length servers) in
         get_definition ~server word)
      words
  in
  Lwt_list.iter_s print_result results

let () =
  let servers = ref ["api.duckduckgo.com"]
  and words = ref [] in
  let options = [
    "-servers",
    Arg.String (fun s -> servers := String.split_on_char ',' s),
    "Specify servers to connect to";
  ] in
  let usage = "Usage: " ^ Sys.argv.(0) ^ " [-servers s1,...,sn] [word ...]" in
  Arg.parse options (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print ~servers:!servers !words)
*)


(* Timeouts, Cancellation, and Choices *)

let get_definition ~(server : string) (word : string) : (string * (string option, exn) result) Lwt.t =
  try%lwt
    let%lwt _resp, body = Cohttp_lwt_unix.Client.get (query_uri ~server word) in
    let%lwt body' = Cohttp_lwt_body.to_string body in
    Lwt.return (word, Ok (get_definition_from_json body'))
  with exn -> Lwt.return (word, Error exn)

let get_definition_with_timeout ~(server : string) (timeout : float) (word : string) : (string * (string option, string) result) Lwt.t =
  Lwt.pick [
    (Lwt_unix.sleep timeout >> Lwt.return (word, Error "Timed out"));
    (let%lwt word, result = get_definition ~server word in
     let result' =
       match result with
       | Ok _ as x -> x
       | Error _ -> Error "Unexpected failure"
     in
     Lwt.return (word, result'));
  ]

let search_and_print ~(servers : string list) (timeout : float) (words : string list) : unit Lwt.t =
  let servers = Array.of_list servers in
  let%lwt results =
    Lwt_list.mapi_p
      (fun i word ->
         let server = servers.(i mod Array.length servers) in
         get_definition_with_timeout  ~server timeout word)
      words
  in
  Lwt_list.iter_s print_result results

let () =
  let servers = ref ["api.duckduckgo.com"]
  and timeout = ref 5.0
  and words = ref [] in
  let options = [
    "-servers",
    Arg.String (fun s -> servers := String.split_on_char ',' s),
    "Specify servers to connect to";
    "-timeout",
    Arg.Set_float timeout,
    "Abandon queries that take longer than this time";
  ] in
  let usage = "Usage: " ^ Sys.argv.(0) ^ " [-servers s1,...,sn] [-timeout secs] [word ...]" in
  Arg.parse options (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print ~servers:!servers !timeout !words)
