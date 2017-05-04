# Concurrent Programming with Lwt

Deokhwan Kim - Version v1.0, 2017-05-09

Below are Lwt translations of [the code examples](https://github.com/realworldocaml/examples) in [Real World OCaml - Chapter 18. Concurrent Programming with Async](https://realworldocaml.org/v1/en/html/concurrent-programming-with-async.html). The section titles follow those in the book for easy cross-reference. Here is the version information of the software components that I have used:

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
    Lwt_io.write_from_exactly w buffer 0 bytes_read >> copy_blocks buffer r w
```

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
  let usage = "Usage: " ^ Sys.argv.(0) ^ " [word ...]" in
  Arg.parse [] (fun w -> words := w :: !words) usage;
  words := List.rev !words;

  (try Lwt_engine.set (new Lwt_engine.libev ())
   with Lwt_sys.Not_available _ -> ());
  Lwt_main.run (search_and_print !words)
```


---

<a name="backtrace">1</a>. It has been [reported](https://github.com/ocsigen/lwt/issues/171) that the backtrace mechanism appears not to work well with the recent versions of OCaml. For the present, the choice between the Ppx constructs and the regular functions (or operators) may be more a matter of style.
