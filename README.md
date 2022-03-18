# Zig Calculator

A calculator engine, capable of parsing equation strings, written in [Zig](https://ziglang.org/).

## Features
- Floating point numbers
- All four operations (+, -, *, /)
- \* and / take precedence over + and -
- Support of nested groups with ( and )
- Function definitions with: `def: name(<parameters>) = <equation>`
- Variable definitions with: `def: name = <equation>`
- Standard variables such as `e` and `pi`
- Standard functions including `sin`, `cos`, `tan`, `sqrt`, `pow`, `log`, etc.
- Units:
  - Converting between units using the `in` operator (e.g. `3km in mi`)
  - Converting between units "on the fly" during calculations, making e.g. `3km * 2mi` possible
  - Handling units in most cases, let it be in brackets or in normal calculations (one exception being function equations and parameters)

## Running
Just run `zig build run` in the root directory.

The engine is located in `/calculator/src` and a cli implementation is located in `/cli/src/main.zig`.
