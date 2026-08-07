//// Gleam consumer of oresoftware/flags-2-env.
////
//// Asserts the contract in EXPECTED.md. Panics on the first disagreement,
//// which exits non-zero and makes `docker run` the whole test.
////
//// Gleam reaches the C core through an Erlang NIF rather than through a shared
//// object loaded at runtime, so there is no library path to configure here.
//// `erlang:load_nif` finds flags2env_nif.so in the priv/ directory of the
//// flags2env_native module, which the Dockerfile assembles under ERL_LIBS.

import flags2env
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/string

const config = ".cli-flags.toml"

type Case {
  Case(label: String, flags: List(String), expected: List(#(String, String)))
}

fn defaults() -> List(#(String, String)) {
  [
    #("APP_ENV", "development"),
    #("COLOR", "true"),
    #("DEBUG", "false"),
    #("PORT", "3000"),
  ]
}

fn overridden() -> List(#(String, String)) {
  [
    #("APP_ENV", "production"),
    #("COLOR", "true"),
    #("DEBUG", "true"),
    #("PORT", "8181"),
  ]
}

fn negated() -> List(#(String, String)) {
  [
    #("APP_ENV", "development"),
    #("COLOR", "false"),
    #("DEBUG", "false"),
    #("PORT", "3000"),
  ]
}

fn cases() -> List(Case) {
  [
    Case("defaults", [], defaults()),
    Case(
      "long flags",
      ["--port", "8181", "--debug=t", "--mode", "production"],
      overridden(),
    ),
    Case(
      "short flags",
      ["-p", "8181", "-d", "1", "--env", "production"],
      overridden(),
    ),
    Case(
      "long aliases",
      ["--listen-port", "8181", "--debug", "1", "--mode", "production"],
      overridden(),
    ),
    Case(
      "joined by =",
      ["--port=8181", "--debug=yes", "--mode=production"],
      overridden(),
    ),
    Case("negation", ["--no-color"], negated()),
  ]
}

fn pad(value: String, width: Int) -> String {
  case string.length(value) >= width {
    True -> value
    False -> pad(value <> " ", width)
  }
}

fn run_case(test_case: Case) -> Int {
  let parsed = flags2env.parse_with_config(["demo", ..test_case.flags], config)

  // Both directions: every declared key matches, and the parser emitted nothing
  // extra. Checking only the first would let a stray key slip through.
  let matches =
    list.all(test_case.expected, fn(pair) {
      dict.get(parsed, pair.0) == Ok(pair.1)
    })
    && dict.size(parsed) == list.length(test_case.expected)

  let status = case matches {
    True -> "ok  "
    False -> "FAIL"
  }
  io.println(
    status
    <> " "
    <> pad(test_case.label, 13)
    <> " demo "
    <> string.join(test_case.flags, " "),
  )

  list.each(test_case.expected, fn(pair) {
    let value = case dict.get(parsed, pair.0) {
      Ok(found) -> found
      Error(_) -> "<missing>"
    }
    io.println("       " <> pair.0 <> "=" <> value)
  })

  case matches {
    True -> 0
    False -> 1
  }
}

pub fn main() {
  let all = cases()
  let failures = list.fold(all, 0, fn(total, one) { total + run_case(one) })

  case failures {
    0 ->
      io.println(
        "\ngleam-app OK: "
        <> int.to_string(list.length(all))
        <> " cases, via an Erlang NIF into oresoftware/flags-2-env",
      )
    _ -> {
      io.println(
        "\ngleam-app: "
        <> int.to_string(failures)
        <> " of "
        <> int.to_string(list.length(all))
        <> " cases disagree with the contract",
      )
      panic as "gleam-app disagrees with the flags-2-env contract"
    }
  }
}
