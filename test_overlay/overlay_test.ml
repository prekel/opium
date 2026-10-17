open Lwt.Infix
open Opium.Std

let check condition message = if not condition then failwith message

let middleware_names app =
  App.to_rock app |> Rock.App.middlewares |> List.map Rock.Middleware.name

let dispatch rock request =
  let filters = Rock.App.middlewares rock |> List.map Rock.Middleware.filter in
  Rock.Filter.apply_all filters (Rock.App.handler rock) request

let request ?(body = "") path =
  Request.create ~body:(Body.of_string body) (Cohttp.Request.make (Uri.of_string path))

let test_flags () =
  let app = App.empty |> App.debug true |> App.verbose true in
  check (middleware_names app = ["Router"; "Trace"; "Debug"])
    "programmatic flags must enable both middlewares" ;
  let app = app |> App.debug false |> App.verbose false in
  check (middleware_names app = ["Router"])
    "programmatic flags must also disable the middlewares"

let test_runner_routes () =
  let calls = ref [] in
  let middleware =
    Rock.Middleware.create ~name:"test" ~filter:(fun next req ->
        calls := "middleware" :: !calls ;
        next req)
  in
  let app =
    App.empty
    |> App.get "/hello/:name" (fun req ->
           calls := "route" :: !calls ;
           respond' (`Json (`Assoc [("name", `String (param req "name"))])))
    |> App.middleware middleware
  in
  let run ?ssl rock ~port =
    check (port = 3000 && ssl = None) "default runner arguments changed" ;
    dispatch rock (request "/hello/Alice") >>= fun response ->
    check (response.code = `OK) "route status changed" ;
    Body.to_string response.body >|= fun body ->
    check (Yojson.Safe.from_string body = `Assoc [("name", `String "Alice")])
      "prepared application must retain routing and path parameters"
  in
  Lwt_main.run (App.start ~run app) ;
  check (List.rev !calls = ["middleware"; "route"])
    "custom runner must retain application middleware"

let test_runner_configuration () =
  let called = ref false in
  let run ?ssl _rock ~port =
    called := true ;
    check (port = 4321) "custom runner did not receive the configured port" ;
    check (ssl = Some (`Crt_file_path "cert.pem", `Key_file_path "key.pem"))
      "custom runner did not receive the configured TLS files" ;
    Lwt.return_unit
  in
  let app =
    App.empty |> App.port 4321 |> App.ssl ~cert:"cert.pem" ~key:"key.pem"
  in
  Lwt_main.run (App.start ~run app) ;
  check !called "custom runner was not called"

exception Runner_failure

let test_runner_failure () =
  let run ?ssl:_ _rock ~port:_ = Lwt.fail Runner_failure in
  let propagated =
    try Lwt_main.run (App.start ~run App.empty) ; false
    with Runner_failure -> true
  in
  check propagated "custom runner failure was not propagated"

let test_runner_cancellation () =
  let cancelled = ref false in
  let thread, _ = Lwt.task () in
  Lwt.on_cancel thread (fun () -> cancelled := true) ;
  let run ?ssl:_ _rock ~port:_ = thread in
  Lwt.cancel (App.start ~run App.empty) ;
  check !cancelled "cancelling App.start must cancel its runner"

let test_json () =
  let payload = `Assoc [("count", `Int 42); ("items", `List [`Bool true; `Null])] in
  let response = respond ~code:`Created (`Json payload) in
  check (response.code = `Created) "JSON response lost its status" ;
  check (Cohttp.Header.get response.headers "content-type" = Some "application/json")
    "JSON response lost its media type" ;
  let body = Lwt_main.run (Body.to_string response.body) in
  let parsed = Lwt_main.run (App.json_of_body_exn (request ~body "/")) in
  check (Yojson.Safe.equal payload parsed) "Yojson request/response round trip failed" ;
  let rejected =
    try
      ignore (Lwt_main.run (App.json_of_body_exn (request ~body:"{" "/"))) ;
      false
    with Yojson.Json_error _ -> true
  in
  check rejected "invalid JSON must fail with Yojson.Json_error"

let test_streaming () =
  let finish, push = App.create_stream () in
  push "first" ;
  push "second" ;
  let response = Lwt_main.run (finish ~code:`Accepted (Lwt.return_unit)) in
  check (response.code = `Accepted) "stream response lost its status" ;
  let body = Lwt_main.run (Body.to_string response.body) in
  check (body = "firstsecond") "0.18 streaming helper no longer works"

(* Check the exported Cohttp callback and default runner signatures, too. *)
let (_ : App.run) = App.run_unix

let (_ : Rock.App.t -> Cohttp_lwt_unix.Server.conn -> Cohttp.Request.t ->
         Body.t -> (Cohttp.Response.t * Body.t) Lwt.t) = App.app_handler

let () =
  List.iter
    (fun (name, test) -> test () ; Printf.printf "PASS %s\n%!" name)
    [ "programmatic debug/verbose", test_flags
    ; "custom runner routing and middleware", test_runner_routes
    ; "custom runner port and TLS", test_runner_configuration
    ; "custom runner failure", test_runner_failure
    ; "custom runner cancellation", test_runner_cancellation
    ; "Yojson helpers", test_json
    ; "0.18 streaming helpers", test_streaming ]
