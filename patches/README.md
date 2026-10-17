# Opium 0.18.0: программный запуск и Yojson

Три патча для официального архива `opium-0.18.0.tbz`. Применять последовательно:

1. `opium.0.18.0-debug-verbose.patch` — перенос `ef2ff0896d7319910b0fbf67072536b3a9fea26c`:
   `App.debug : bool -> builder` и `App.verbose : bool -> builder`.
2. `opium.0.18.0-customizable-start.patch` — перенос `38f2d867b7ac12e163fa3071812bd7a8a5db0fb0`:
   `App.start ~run`, экспорт `App.app_handler`, `App.run_unix`, `App.ssl_t` и `App.run`.
   Использует `Opium_kernel.Rock` из релиза 0.18.0.
3. `opium.0.18.0-yojson.patch` — перенос JSON API из `customizable_start`, по мотивам
   `8222246ec4d34f23475b408ba81c2353c79709b5`: `Yojson.Safe.t`, `from_string`, `to_string`,
   зависимости, примеры и документация. Streaming API и настраиваемый 404 из 0.18.0 сохраняются.

Тесты и скрипт проверки в патчи не входят. Основной checkout репозитория менять
на 0.18.0 для использования этих файлов не требуется.

## Вставка в opam overlay

Скопировать **только три `.patch`** в каталог `files/` пакета:

```text
packages/opium/opium.0.18.0/
├── opam
└── files/
    ├── opium.0.18.0-debug-verbose.patch
    ├── opium.0.18.0-customizable-start.patch
    └── opium.0.18.0-yojson.patch
```

В существующем opam-файле **заменить** блок `depends:` на следующий.
Замена `ezjsonm` на `yojson` нужна в самом overlay: opam разрешает зависимости
до применения патчей, поэтому изменения `opium.opam` внутри исходников недостаточно.
Ограничение Cmdliner сохраняет совместимость со старым CLI API.

```opam
depends: [
  "ocaml" {>= "4.04.1"}
  "dune" {>= "1.11"}
  "opium_kernel" {= "0.18.0"}
  "cohttp-lwt-unix"
  "yojson" {>= "1.6.0"}
  "lwt"
  "logs"
  "cmdliner" {< "2.0.0"}
  "ppx_fields_conv"
  "ppx_sexp_conv"
  "re"
  "magic-mime"
  "alcotest" {with-test}
]
```

Добавить следующие поля. Если они уже есть, объединить списки, сохранив
порядок трёх патчей и существующие необходимые записи:

```opam
extra-files: [
  ["opium.0.18.0-debug-verbose.patch" "sha256=3e22a6efa8451061019b42dbd49afdabc734444d028ec82b3b4b52f853738252"]
  ["opium.0.18.0-customizable-start.patch" "sha256=6c0da5ea1eb3bae7d950c4ed1475cad488a52831799b06b29a905ff423437a1c"]
  ["opium.0.18.0-yojson.patch" "sha256=9df96db9c8a1f55c679c45a480d94c5e8274a2e2701969ace1f2bc83ba2924e3"]
]

patches: [
  "opium.0.18.0-debug-verbose.patch"
  "opium.0.18.0-customizable-start.patch"
  "opium.0.18.0-yojson.patch"
]
```

`extra-files` содержит имена относительно `files/`, а `patches` — относительно
корня распакованных исходников, куда opam скопирует эти файлы. Начиная с opam 2.3
файлы из `files/` без записи в `extra-files` не копируются.
[Документация opam](https://opam.ocaml.org/doc/Manual.html#opamfield-extra-files).

Исходный `url` и checksum архива оставить без изменений:

```opam
url {
  src: "https://github.com/rgrinberg/opium/releases/download/0.18.0/opium-0.18.0.tbz"
  checksum: [
    "sha256=f80ccf9c36665c2db240482eeb0cc968a9e66ad2b7a811298658df52f84b5e28"
    "sha512=345585719e58b8a08b45244123f03e094a9c67ad8c2ee903dac4d8b646703cfea74ab87a82f43cf6113ad394c296bddb4bb5fbd910ed8511693b5ec6867baece"
  ]
}
```

Для пакета `opium_kernel.0.18.0` эти патчи не нужны. Его API остаётся релизным.
После редактирования патчей пересчитать SHA256 и обновить `extra-files`:

```sh
sha256sum patches/opium.0.18.0-*.patch
opam lint /path/to/overlay/packages/opium/opium.0.18.0/opam
```

## API и совместимость

Обычный `App.start app` запускает прежний Cohttp-сервер. Для своего запуска:

```ocaml
let run ?ssl rock ~port =
  let callback = Opium.App.app_handler rock in
  (* Configure your Cohttp server here using callback, port and ssl. *)
  (* Return its cancellable unit Lwt.t promise. *)
  ...

let server =
  Opium.App.empty
  |> Opium.App.debug true
  |> Opium.App.verbose true
  |> Opium.App.start ~run
```

Патчи сохраняют поведение оригинальных изменений: `run_command` и `run_command'`
не принимают `~run`; программные `debug`/`verbose` применяются при прямом запуске,
а CLI перезаписывает их своими флагами, включая `false` при отсутствии флага.

JSON API намеренно меняется с Ezjsonm на Yojson. JSON helpers ожидают и возвращают
`Yojson.Safe.t`, а ошибка синтаксиса приходит как `Yojson.Json_error`. Старый код,
передающий `Ezjsonm.t` или ловящий исключения Ezjsonm, нужно адаптировать.

`Opium_core` этими тремя патчами не добавляется. Если приложение использует
его публичные `Service` и `Filter`, совместимый модуль может состоять из aliases:

```ocaml
module Service = Opium.Std.Rock.Service
module Filter = Opium.Std.Rock.Filter
```

Адаптер `typed-endpoint-opium` использует общий API Opium 0.17.1/0.18.0,
читает тело как строку и сам сериализует ответы через Yojson. Отдельная ветка
адаптера под `customizable_start` для этих патчей не требуется.

## Проверка

Существующий switch должен содержать зависимости Opium 0.18.0, Yojson и Cmdliner < 2.
Для проверки текущего адаптера также нужны зависимости `typed-endpoint-opium`
и совместимая установленная версия ядра `typed-endpoint`.

```sh
python3 scripts/verify-opium-overlay.py --switch=/path/to/switch
python3 scripts/verify-opium-overlay.py --switch=/path/to/switch --typed-endpoint=../typed-endpoint
```

Скрипт скачивает официальный архив, проверяет SHA512, применяет патчи без fuzz
и offsets и собирает production-пакет без дополнительных тестов. Затем собирает
upstream-примеры и запускает отдельные проверки `test_overlay/`: настройки,
маршрутизацию и middleware в собственном runner, port/TLS, ошибки и отмену runner,
JSON helpers и streaming. С `--typed-endpoint` пересобирает `.ml` и `.mli` адаптера
из указанного checkout и проверяет маршрут, JSON-ответ, 405/Allow и лимит тела.
Исходники и тесты собираются во временной директории; установленные пакеты
и указанный checkout `typed-endpoint` не изменяются. Требуется Python >= 3.12.
