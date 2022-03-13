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

## Running
Just run `zig build run` in the root directory.

The engine is located in `/calculator/src` and a cli implementation is located in `/cli/src/main.zig`.