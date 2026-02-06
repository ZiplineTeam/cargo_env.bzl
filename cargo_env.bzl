"""re-export to allow syntax sugar: load("@cargo_env.bzl", "cargo_env")"""

load("//cargo_env:cargo_env.bzl", _cargo_env = "cargo_env", _env_wrapper = "env_wrapper")

cargo_env = _cargo_env
env_wrapper = _env_wrapper
