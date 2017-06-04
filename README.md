# Concurrent Programming with Lwt

Deokhwan Kim - Version v1.0, 2017-05-09

Below are [Lwt](https://github.com/ocsigen/lwt) translations of [the code examples](https://github.com/realworldocaml/examples) in [Real World OCaml - Chapter 18. Concurrent Programming with Async](https://realworldocaml.org/v1/en/html/concurrent-programming-with-async.html). The section titles follow those in the book for easy cross-reference. Here is the version information of the software components that I have used:

```bash
$ ocamlc -version
4.04.1
$ opam show --field=version lwt
3.0.0
$ opam show --field=version cohttp
0.22.0
$ utop -version
The universal toplevel for OCaml, version 1.19.3, compiled for OCaml version 4.04.1
```

The latest version of this document is available at https://github.com/dkim/rwo-lwt/.


## Async Basics

#### OCaml utop (part 3)

```ocaml
# #require "lwt.unix";;
# #require "lwt.ppx";;
# let file_contents filename =
    Lwt_io.with_file ~mode:Lwt_io.input filename
      (fun channel -> Lwt_io.read channel);;
val file_contents : string -> string Lwt.t = <fun>
```

#### OCaml utop (part 4)

```ocaml
# let contents = file_contents "test.txt";;
val contents : string Lwt.t = <abstr>
# Lwt.state contents;;  (* if test.txt exists *)
- : string Lwt.state = Lwt.Return "This is only a test.\n"
# Lwt.state contents;;  (* if test.txt does not exist *)
- : string Lwt.state =
Lwt.Fail (Unix.Unix_error (Unix.ENOENT, "open", "test.txt"))
```

#### OCaml utop (part 5)

```ocaml
# contents;;
- : string = "This is only a test.\n"
```

#### OCaml utop (part 7)

```ocaml
# Lwt.bind;;
- : 'a Lwt.t -> ('a -> 'b Lwt.t) -> 'b Lwt.t = <fun>
```

I will use [`let%lwt x = e1 in e2`](https://ocsigen.org/lwt/3.0.0/api/Ppx_lwt) in preference to `Lwt.bind e1 (fun x -> e2)` and `e1 >>= (fun x -> e2)`. The Lwt manual states that the former will produce better backtraces than the latter <sup>\[[1](#backtrace)\]</sup>:

> Backtrace support
>
> In debug mode, the `lwt` and `let%lwt` constructs will properly propagate backtraces.
>
> \- https://ocsigen.org/lwt/3.0.0/manual/

> `val bind : 'a t -> ('a -> 'b t) -> 'b t`
>
> Note that `bind` will not propagate backtraces correctly.
>
> \- https://ocsigen.org/lwt/3.0.0/api/Lwt

#### OCaml utop (part 8)

```ocaml
# let save filename ~contents =
    Lwt_io.with_file ~mode:Lwt_io.output filename
      (fun channel -> Lwt_io.write channel contents);;
val save : string -> contents:string -> unit Lwt.t = <fun>
# let uppercase_file filename =
    let%lwt text = file_contents filename in
    save filename ~contents:(String.uppercase_ascii text);;
val uppercase_file : string -> unit Lwt.t = <fun>
# uppercase_file "test.txt";;
- : unit = ()
# file_contents "test.txt";;
- : string = "THIS IS ONLY A TEST.\n"
```

#### OCaml utop (part 10)

```ocaml
# let count_lines filename =
    let%lwt text = file_contents filename in
    String.split_on_char '\n' text |> List.length;;
Error: This expression has type int but an expression was expected of type 'a Lwt.t
```

#### OCaml utop (part 11)

```ocaml
# Lwt.return;;
- : 'a -> 'a Lwt.t = <fun>
# let three = Lwt.return 3;;
val three : int Lwt.t = <abstr>
# three;;
- : int = 3
```

#### OCaml utop (part 12)

```ocaml
# let count_lines filename =
    let%lwt text = file_contents filename in
    String.split_on_char '\n' text |> List.length |> Lwt.return;;
val count_lines : string -> int Lwt.t = <fun>
```

#### OCaml utop (part 13)

```ocaml
# Lwt.map;;
- : ('a -> 'b) -> 'a Lwt.t -> 'b Lwt.t = <fun>
```

As with `Lwt.bind`, I will use the combination of the `let%lwt` construct and the `Lwt.return` function rather than `Lwt.map`.<sup>\[[1](#backtrace)\]</sup>


### Ivars and Upon

#### OCalm utop (part 15)

```ocaml
# let waiter, wakener = Lwt.wait ();;
val waiter : '_a Lwt.t = <abstr>
val wakener : '_a Lwt.u = <abstr>
# Lwt.state waiter;;
- : '_a Lwt.state = Lwt.Sleep
# Lwt.wakeup wakener  "Hello";;
- : unit = ()
# Lwt.state waiter;;
- : string Lwt.state = Lwt.Return "Hello"
```

#### OCaml utop (part 16)

```ocaml
# module type Delayer_intf = sig
    type t
    val create : float -> t
    val schedule : t -> (unit -> 'a Lwt.t) -> 'a Lwt.t
  end;;
module type Delayer_intf =
  sig
    type t
    val create : float -> t
    val schedule : t -> (unit -> 'a Lwt.t) -> 'a Lwt.t
  end
```

#### OCaml utop (part 17)

```ocaml
# Lwt.on_success;;
- : 'a Lwt.t -> ('a -> unit) -> unit = <fun>
# Lwt.on_failure;;
- : 'a Lwt.t -> (exn -> unit) -> unit = <fun>
# Lwt.on_termination;;
- : 'a Lwt.t -> (unit -> unit) -> unit = <fun>
# Lwt.on_any;;
- : 'a Lwt.t -> ('a -> unit) -> (exn -> unit) -> unit = <fun>
```

#### OCaml utop (part 18)

```ocaml
# module Delayer : Delayer_intf = struct
    type t = {delay: float; jobs: (unit -> unit) Queue.t}

    let create delay = {delay; jobs = Queue.create ()}

    let schedule t thunk =
      let waiter, wakener = Lwt.wait () in
      Queue.add
        (fun () ->
           Lwt.on_any (thunk ()) (Lwt.wakeup wakener) (Lwt.wakeup_exn wakener))
        t.jobs;
      Lwt.on_termination (Lwt_unix.sleep t.delay) (Queue.take t.jobs);
      waiter
  end;;
module Delayer : Delayer_intf
```


## Examples: An Echo Server

#### OCaml

```ocaml
let rec copy_blocks buffer r w =
  match%lwt Lwt_io.read_into r buffer 0 (Bytes.length buffer) with
  | 0 -> Lwt.return_unit
  | bytes_read ->
    let%lwt () = Lwt_io.write_from_exactly w buffer 0 bytes_read in
    copy_blocks buffer r w
```

`let%lwt () = e1 in e2` can be shortened to [`e1 >> e2`](https://ocsigen.org/lwt/3.0.0/api/Ppx_lwt#2_Sequence), but `>>` will get [deprecated](https://github.com/ocsigen/lwt/issues/387) in the near future.

#### OCaml (part 1)

```ocaml
let run () =
  ((let%lwt server =
      Lwt_io.establish_server (Lwt_unix.ADDR_INET (Unix.inet_addr_any, 8765))
        (fun (r, w) ->
           let buffer = Bytes.create (16 * 1024) in
           copy_blocks buffer r w)
    in
    Lwt.return server) : Lwt_io.server Lwt.t) |> ignore
```

#### OCaml (part 2)

```ocaml
let never_terminate = fst (Lwt.wait ())

let () =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  run ();
  Lwt_main.run never_terminate
```


### Improving the Echo Server

#### OCaml

```ocaml
let run uppercase port =
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

let () =
  let uppercase = ref false
  and port = ref 8765 in
  let options =
    Arg.align [
      ("-uppercase",
       Arg.Set uppercase,
       " Convert to uppercase before echoing back");
      ("-port",
       Arg.Set_int port,
       "num Port to listen on (default 8765)");
    ]
  in
  let usage = "Usage: " ^ Sys.executable_name ^ " [-uppercase] [-port num]" in
  Arg.parse
    options
    (fun arg -> raise (Arg.Bad (Printf.sprintf "invalid argument -- '%s'" arg)))
    usage;

  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (run !uppercase !port)
```

[The Lwt manual](https://ocsigen.org/lwt/3.0.0/api/Lwt_stream) states that the `Lwt_stream` module may get deprecated or redesigned, and suggests considering alternatives, such as Simon Cruanes's [lwt-pipe](https://github.com/c-cube/lwt-pipe). Below is an equivalent version of the code above that uses lwt-pipe.

```bash
$ opam pin add -k git lwt-pipe https://github.com/c-cube/lwt-pipe.git
$ opam install lwt-pipe
```

```ocaml
let run uppercase port =
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
```


## Example: Searching Definitions with DuckDuckGo

```bash
$ opam install tls cohttp       # Or opam install lwt_ssl cohttp
```


### URI Handling

#### OCaml

```ocaml
let query_uri =
  let base_uri = Uri.of_string "https://api.duckduckgo.com/?format=json" in
  (fun query -> Uri.add_query_param base_uri ("q", [query]))
```


### Parsing JSON Strings

#### OCaml (part 1)

```ocaml
let get_definition_from_json json =
  match Yojson.Safe.from_string json with
  | `Assoc kv_list ->
    let find key =
      match List.assoc key kv_list with
      | exception Not_found -> None
      | `String "" -> None
      | s -> Some (Yojson.Safe.to_string s)
    in
    begin match find "Abstract" with
    | Some _ as x -> x
    | None -> find "Definition"
    end
  | _ -> None
```


### Executing an HTTP Client Query

#### OCaml (part 2)

```ocaml
let get_definition word =
  let%lwt _resp, body = Cohttp_lwt_unix.Client.get (query_uri word) in
  let%lwt body' = Cohttp_lwt_body.to_string body in
  Lwt.return (word, get_definition_from_json body')
```

#### OCaml utop (part 28)

```ocaml
# #require "cohttp.lwt";;
# Cohttp_lwt_unix.Client.get;;
- : ?ctx:Cohttp_lwt_unix.Client.ctx -> ?headers:Cohttp.Header.t -> Uri.t -> (Cohttp_lwt.Response.t * Cohttp_lwt_body.t) Lwt.t = <fun>
```

#### OCaml (part 3)

```ocaml
let print_result (word, definition) =
  Lwt_io.printf "%s\n%s\n\n%s\n\n"
    word
    (String.init (String.length word) (fun _ -> '-'))
    (match definition with
     | None -> "No definition found"
     | Some def ->
       Format.pp_set_margin Format.str_formatter 70;
       Format.pp_print_text Format.str_formatter def;
       Format.flush_str_formatter ())
```

#### OCaml (part 4)

```ocaml
let search_and_print words =
  let%lwt results = Lwt_list.map_p get_definition words in
  Lwt_list.iter_s print_result results
```

#### OCaml utop (part 29)

```ocaml
# Lwt_list.map_p;;
- : ('a -> 'b Lwt.t) -> 'a list -> 'b list Lwt.t = <fun>
```

#### OCaml (part 1)

```ocaml
let search_and_print words =
  Lwt_list.iter_p
    (fun word ->
       let%lwt result = get_definition word in
       print_result result)
    words
```

#### OCaml utop (part 30)

```ocaml
# Lwt_list.iter_p;;
- : ('a -> unit Lwt.t) -> 'a list -> unit Lwt.t = <fun>
```

#### OCaml (part 5)

```ocaml
let () =
  let words = ref [] in
  let usage = "Usage: " ^ Sys.executable_name ^ " [word ...]" in
  Arg.parse [] (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print !words)
```


## Exception Handling

#### OCaml utop (part 31)

```ocaml
# let maybe_raise =
    let should_fail = ref false in
    fun () ->
      let will_fail = !should_fail in
      should_fail := not will_fail;
      let%lwt () = Lwt_unix.sleep 0.5 in
      if will_fail then [%lwt raise Exit] else Lwt.return_unit;;
val maybe_raise : unit -> unit Lwt.t = <fun>
# maybe_raise ();;
- : unit = ()
# maybe_raise ();;
Exception: Pervasives.Exit.
Raised at file "src/core/lwt.ml", line 805, characters 22-23
Called from file "src/unix/lwt_main.ml", line 34, characters 8-18
Called from file "toplevel/toploop.ml", line 180, characters 17-56
```

Note that I wrote `[%lwt raise Exit]` rather than `Lwt.fail Exit`. The Lwt manual states that the former will produce better backtraces than the latter <sup>\[[1](#backtrace)\]</sup>:

> It allows to encode the old `raise_lwt <e>` as `[%lwt raise <e>]`, ...
>
> \- https://ocsigen.org/lwt/3.0.0/api/Ppx_lwt

> `raise_lwt exn`
>
> which is the same as Lwt.fail exn but with backtrace support.
>
> \- https://ocsigen.org/lwt/3.0.0/manual/

#### OCaml utop (part 32)

```ocaml
# let handle_error () =
    try
      let%lwt () = maybe_raise () in
      Lwt.return "success"
    with _ -> Lwt.return "failure";;
val handle_error : unit -> string Lwt.t = <fun>
# handle_error ();;
- : string = "success"
# handle_error ();;
Exception: Pervasives.Exit.
Raised at file "src/core/lwt.ml", line 805, characters 22-23
Called from file "src/unix/lwt_main.ml", line 34, characters 8-18
Called from file "toplevel/toploop.ml", line 180, characters 17-56
```

#### OCaml utop (part 33)

```ocaml
# let handle_error () =
    try%lwt
      let%lwt () = maybe_raise () in
      Lwt.return "success"
    with _ -> Lwt.return "failure";;
val handle_error : unit -> string Lwt.t = <fun>
# handle_error ();;
- : string = "success"
# handle_error ();;
- : string = "failure"
```

Although the manual does not state it explicitly, `try%lwt ... with ...` appears to be intended to provide a better backtrace than `Lwt.catch`.<sup>\[[1](#backtrace)\]</sup> For instance, the `handle_error` function is expanded to:

```ocaml
let handle_error () =
  Lwt.backtrace_catch (fun exn  -> try raise exn with | exn -> exn)
    (fun ()  ->
       Lwt.backtrace_bind (fun exn  -> try raise exn with | exn -> exn)
         (maybe_raise ())
         (fun ()  -> Lwt.return "success"))
    (function | _ -> Lwt.return "failure")
```


### Monitors

Lwt does not have a concept corresponding to a monitor.


### Example: Handling Exceptions with DuckDuckGo

#### OCaml (part 1)

```ocaml
let query_uri ~server query =
  let base_uri =
    Uri.of_string (String.concat "" ["https://"; server; "/?format=json"])
  in
  Uri.add_query_param base_uri ("q", [query])
```

#### OCaml (part 1)

```ocaml
let get_definition ~server word =
  try%lwt
    let%lwt _resp, body = Cohttp_lwt_unix.Client.get (query_uri ~server word) in
    let%lwt body' = Cohttp_lwt_body.to_string body in
    Lwt.return (word, Ok (get_definition_from_json body'))
  with _ -> Lwt.return (word, Error "Unexpected failure")
```

#### OCaml (part 2)

```ocaml
let print_result (word, definition) =
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
```

```ocaml
let search_and_print ~servers words =
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
  let options =
    Arg.align [
      ("-servers",
       Arg.String (fun s -> servers := String.split_on_char ',' s),
       "s1,...,sn Specify servers to connect to");
    ]
  in
  let usage = "Usage: " ^ Sys.executable_name ^ " [-servers s1,...,sn] [word ...]" in
  Arg.parse options (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print ~servers:!servers !words)
```


## Timeouts, Cancellation, and Choices

#### OCaml utop (part 39)

```ocaml
# let both x y =
    let%lwt x' = x
    and y' = y in
    Lwt.return (x', y');;
val both : 'a Lwt.t -> 'b Lwt.t -> ('a * 'b) Lwt.t = <fun>
# let string_and_float =
    both
      (let%lwt () = Lwt_unix.sleep 0.5 in
       Lwt.return "A")
      (let%lwt () = Lwt_unix.sleep 0.25 in
       Lwt.return 32.33);;
val string_and_float : (string * float) Lwt.t = <abstr>
# string_and_float;;
- : string * float = ("A", 32.33)
```

#### OCaml utop (part 40)

```ocaml
# Lwt.choose [
    (let%lwt () = Lwt_unix.sleep 0.5 in
     Lwt.return "half a second");
    (let%lwt () = Lwt_unix.sleep 10. in
     Lwt.return "ten seconds");
  ];;
- : string = "half a second"
```

#### OCaml utop (part 41)

```ocaml
# Lwt.pick;;
- : 'a Lwt.t list -> 'a Lwt.t = <fun>
```

#### OCaml (parts 1 and 2)

```ocaml
let get_definition ~server word =
  try%lwt
    let%lwt _resp, body = Cohttp_lwt_unix.Client.get (query_uri ~server word) in
    let%lwt body' = Cohttp_lwt_body.to_string body in
    Lwt.return (word, Ok (get_definition_from_json body'))
  with exn -> Lwt.return (word, Error exn)

let get_definition_with_timeout ~server timeout word =
  Lwt.pick [
    (let%lwt () = Lwt_unix.sleep timeout in
     Lwt.return (word, Error "Timed out"));
    (let%lwt word, result = get_definition ~server word in
     let result' =
       match result with
       | Ok _ as x -> x
       | Error _ -> Error "Unexpected failure"
     in
     Lwt.return (word, result'));
  ]

let search_and_print ~servers timeout words =
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
  let options =
    Arg.align [
      ("-servers",
       Arg.String (fun s -> servers := String.split_on_char ',' s),
       "s1,...,sn Specify servers to connect to");
      ("-timeout",
       Arg.Set_float timeout,
       "secs Abandon queries that take longer than this time");
    ]
  in
  let usage = "Usage: " ^ Sys.executable_name ^ " [-servers s1,...,sn] [-timeout secs] [word ...]" in
  Arg.parse options (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print ~servers:!servers !timeout !words)
```

`Cohttp_lwt_unix.Client.get` does not take the labeled `~interrupt` argument unlike `Cohttp_async.Client.get`. However, the thread that `Cohttp_lwt_unix.Client.get` returns is [cancelable](https://ocsigen.org/lwt/3.0.0/api/Lwt#2_Cancelablethreads) and can be naturally used with `Lwt.pick`.


## Working with System Threads

#### OCaml utop (part 42)

```ocaml
# let rec range ?(acc = []) start stop =
    if start >= stop then List.rev acc
    else range ~acc:(start :: acc) (start + 1) stop;;
val range : ?acc:int list -> int -> int -> int list = <fun>
# let def = Lwt_preemptive.detach (fun () -> range 1 10) ();;
val def : int list Lwt.t = <abstr>
# def;;
- : int list = [1; 2; 3; 4; 5; 6; 7; 8; 9]
```

#### OCaml utop (part 43)

```ocaml
# let rec every ?(stop = never_terminate) span (f : unit -> unit Lwt.t) : unit Lwt.t =
    if Lwt.is_sleeping stop then
      let%lwt () = f () in
      let%lwt () = Lwt.pick [Lwt_unix.sleep span; Lwt.protected stop] in
      every ~stop span f
    else Lwt.return_unit;;
val every : ?stop:unit Lwt.t -> float -> (unit -> unit Lwt.t) -> unit Lwt.t = <fun>
# let log_delays thunk =
    let start = Unix.gettimeofday () in
    let print_time () =
      let diff = Unix.gettimeofday () -. start in
      Lwt_io.printf "%f, " diff
    in
    let d = thunk () in
    let%lwt () = every 0.1 ~stop:d print_time in
    let%lwt () = d in
    let%lwt () = print_time () in
    Lwt_io.print "\n";;
val log_delays : (unit -> unit Lwt.t) -> unit Lwt.t = <fun>
```

#### OCaml utop

```ocaml
# log_delays (fun () -> Lwt_unix.sleep 0.5);;
0.000006, 0.101822, 0.201969, 0.306260, 0.411472, 0.505199,
```

#### OCalm utop

```ocaml
# let busy_loop () =
    let x = ref None in
    for i = 1 to 500_000_000 do x := Some i done;;
val busy_loop : unit -> unit = <fun>
# log_delays (fun () -> Lwt.return (busy_loop ()));;
6.890156,
- : unit = ()
```

#### OCaml utop

```ocaml
# log_delays (fun () -> Lwt_preemptive.detach busy_loop ());;
0.000033, 0.158420, 0.264950, 0.370093, 0.475191, 0.585002, 0.685192, 0.786619,
0.894304, 0.997954, 1.103635, 1.213693, 1.316856, 1.426929, 1.583395, 1.686367,
1.786517, 1.894609, 1.998529, 2.103606, 2.208725, 2.363542, 2.571035, 2.680959,
2.945979, 3.056136, 3.161278, 3.430440, 3.531169, 3.742274, 3.847282, 3.951309,
4.114742, 4.215642, 4.315771, 4.421812, 4.530823, 4.741970, 4.848297, 5.008062,
5.114670, 5.430785, 5.535985, 5.644637, 5.802193, 6.015593, 6.226784, 6.330944,
6.546150, 6.703104, 6.806751, 6.912780, 6.992610,
- : unit = ()
```

#### OCaml utop

```ocaml
# let noallc_busy_loop () =
    for _i = 0 to 500_000_000 do () done;;
val noallc_busy_loop : unit -> unit = <fun>
# log_delays (fun () -> Lwt_preemptive.detach noallc_busy_loop ());;
0.000010, 0.137578, 0.240112, 0.345218, 0.450686, 0.555763, 0.660168, 0.766587,
0.872521, 0.977615, 1.078819, 1.184021, 1.289587, 1.394786, 1.552426, 1.657563,
1.764036, 1.922921, 2.078783, 2.287458, 2.501932, 2.663988, 2.768908, 2.978174,
3.188819, 3.297128, 3.460475, 3.568800, 3.670217, 3.803641, 3.803730,
- : unit = ()
```


---

<a name="backtrace">1</a>. It has been [reported](https://github.com/ocsigen/lwt/issues/171) that the backtrace mechanism appears not to work well with the recent versions of OCaml. For the present, the choice between the Ppx constructs and the regular functions (or operators) may be more a matter of style.
