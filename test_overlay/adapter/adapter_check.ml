open Lwt.Infix
open Opium.Std
module Backend = Typed_endpoint_opium

let check condition message = if not condition then failwith message

let dispatch app req =
  let rock = App.to_rock app in
  let filters = Rock.App.middlewares rock |> List.map Rock.Middleware.filter in
  Rock.Filter.apply_all filters (Rock.App.handler rock) req

let request ?(meth = `GET) ?(body = "") path =
  Request.create ~body:(Body.of_string body)
    (Cohttp.Request.make ~meth (Uri.of_string path))

let test () =
  let route =
    Backend.route `GET "/hello/:name" (fun req ->
        Backend.respond_json (`Assoc [("name", `String (Backend.param req "name"))]))
  in
  let app = Backend.mount route App.empty in
  dispatch app (request "/hello/Alice") >>= fun response ->
  check (response.code = `OK) "adapter route status changed" ;
  Body.to_string response.body >>= fun body ->
  check (Yojson.Safe.from_string body = `Assoc [("name", `String "Alice")])
    "adapter path parameter / JSON response failed" ;
  dispatch app (request ~meth:`POST "/hello/Alice") >>= fun response ->
  check (response.code = `Method_not_allowed) "adapter 405 handling failed" ;
  check (Cohttp.Header.get response.headers "allow" = Some "GET")
    "adapter 405 response lost its Allow header" ;
  Backend.body_to_string ~max_bytes:3 (request ~body:"1234" "/") >|= fun result ->
  check (result = Error `Too_large) "adapter request body limit failed"

let () =
  Lwt_main.run (test ()) ;
  print_endline "PASS current typed-endpoint Opium adapter"
