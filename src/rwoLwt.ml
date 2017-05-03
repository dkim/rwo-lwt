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
