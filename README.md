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


---

<a name="backtrace">1</a>. It has been [reported](https://github.com/ocsigen/lwt/issues/171) that the backtrace mechanism appears not to work well with the recent versions of OCaml. For the present, the choice between the Ppx constructs and the regular functions (or operators) may be more a matter of style.
