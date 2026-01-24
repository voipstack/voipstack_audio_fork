# Crystal Language Reference for LLMs with Ruby Knowledge (Expert-Level)

A comprehensive reference to teach an LLM familiar with Ruby how to write high-quality, idiomatic Crystal code, highlighting language features, best practices, and advanced patterns.

---

## 1. Overview
- Crystal is statically typed and compiled to native code.
- Syntax heavily inspired by Ruby.
- Key features: type inference, nil safety, union types, macros, fibers, channels, native C interop.
- Differences from Ruby: static typing, compile-time macros, optional type annotations, no runtime reflection for most types.
- Best practice: leverage static typing and compile-time checks for safety and performance.

---

## 2. Basic Syntax

### Variables and Constants
```crystal
x = 42              # Type inferred as Int32
y : String = "hello"  # Explicit type
PI = 3.14159         # Constants are immutable
```
- Use explicit types for public API clarity.

### Methods
```crystal
def greet(name : String) : String
  "Hello, #{name}"
end
```
- Annotate return type for clarity and type safety.

### Blocks
```crystal
[1,2,3].each do |n|
  puts n
end
```
- Use `{}` for short, single-expression blocks, `do..end` for multiline.

---

## 3. Control Flow
```crystal
if x > 10
  puts "big"
elsif x == 10
  puts "ten"
else
  puts "small"
end
```
- Use `unless` and `case` idiomatically.
- Favor `while` or `for` over `loop` for clarity.

---

## 4. Types and Type System

### Basic Types
- `Int32`, `Int64`, `Float32`, `Float64`, `Bool`, `String`, `Char`
- Arrays: `Array(Int32)`
- Tuples: `{Int32, String}`
- Hashes: `Hash(String, Int32)`

### Union Types & Nil Safety
```crystal
x : Int32 | Nil = nil
x = 10
puts x?  # Safe access
```
- Use `?` and union types to handle optional values safely.

### Type Inference
- Prefer inferred types for local variables; use explicit types for public APIs.

---

## 5. Classes, Modules, and Interfaces

### Classes
```crystal
class Person
  property name : String

  def initialize(@name : String)
  end

  def greet : String
    "Hi, #{@name}"
  end
end
```
- Use `property` to generate getters/setters.
- Annotate return types for public methods.

### Modules and Mixins
```crystal
module Greeter
  def greet : String
    "Hello!"
  end
end
```
- Mix in modules to share behavior instead of inheritance when appropriate.

### Interfaces & Abstract Classes
```crystal
abstract class Animal
  abstract def speak : String
end

class Dog < Animal
  def speak : String
    "Woof!"
  end
end
```
- Use abstract classes or modules to define contracts for polymorphism.

---

## 6. Concurrency (Fibers & Channels)
```crystal
channel = Channel(Int32).new
spawn channel.send(42)
puts channel.receive
```
- Use `spawn` for lightweight tasks.
- Use channels for communication; avoid shared mutable state.
- Prefer `Fiber.scheduler` and async I/O for high-performance applications.

---

## 7. Macros (Compile-Time Metaprogramming)
```crystal
macro define_getter(name)
  def {{name.id}} : typeof(@{{name.id}})
    @{{name.id}}
  end
end
```
- Use macros for boilerplate reduction, DSLs, or compile-time optimizations.
- Avoid runtime logic inside macros; they execute at compile time.

---

## 8. Collections

### Arrays
```crystal
arr = [1,2,3]
arr << 4           # Push
arr.map(&.to_s)    # Map using method reference
```
- Prefer `map`, `select`, `reject` over manual loops for clarity.

### Hashes
```crystal
h = {"a" => 1, "b" => 2}
h["c"] = 3
```
- Use `Hash.new(default)` to simplify defaults.

### Ranges
```crystal
(1..5).each do |i|
  puts i
end
```
- Use exclusive ranges `...` when needed.

---

## 9. Exception Handling
```crystal
begin
  1 / 0
rescue ex : DivisionByZero
  puts "Cannot divide by zero"
end
```
- Prefer typed exceptions to catch only expected errors.
- Avoid using exceptions for control flow.

---

## 10. Crystal-Specific Best Practices
1. Use static typing to prevent errors and improve performance.
2. Prefer `?` for nil safety.
3. Leverage union types for optional and polymorphic data.
4. Use macros for repetitive code or compile-time optimization.
5. Use fibers and channels for concurrency; avoid shared state.
6. Annotate public API types for clarity.
7. Write idiomatic Crystal: prefer methods like `map`, `select`, `reduce`.
8. Use `Crystal::Printf` or `IO::Buffer` for high-performance output when needed.

---

## 11. Quick Reference Table: Ruby → Crystal
| Ruby                | Crystal                           |
|--------------------|----------------------------------|
| `puts "hi"`         | `puts "hi"`                       |
| `x = 1`             | `x = 1` (type inferred)           |
| `def foo(a)`         | `def foo(a : Int32)`               |
| `nil`               | `nil`                             |
| `Array.new`         | `[1,2,3]` / `Array(Int32).new`    |
| `Hash.new`          | `Hash(String, Int32).new`         |
| `each do |x|`       | `each do |x|`                     |
| `module M`          | `module M`                        |
| `class A`           | `class A`                         |
| `rescue`            | `rescue ex : SomeError`           |
| `Thread.new`        | `spawn` + `Channel`               |

---

## 12. Teaching Tips for LLMs (Expanded)
To enable an LLM to generate high-quality Crystal code, focus on the following strategies:

### 12.1 Understanding Crystal Concepts
- **Static Typing**: LLM should recognize type annotations, type inference, and union types.
- **Nil Safety**: Use `?` operator and union types to avoid runtime errors.
- **Compile-Time Macros**: Distinguish compile-time evaluation from runtime metaprogramming.
- **Fibers & Channels**: Understand concurrency patterns and safe communication.

### 12.2 Idiomatic Code Generation
- Favor immutable variables and clear public API types.
- Prefer functional collection methods (`map`, `select`, `reduce`) over loops when possible.
- Use concise and readable code blocks (`do..end` for multi-line, `{}` for single-line).
- Follow Crystal naming conventions and style: snake_case for methods, CamelCase for classes/modules.

### 12.3 Error Handling and Safety
- Catch only specific exceptions; avoid generic rescuing.
- Use typed variables to prevent unintended type errors.
- Recognize patterns where exceptions should not be used for control flow.

### 12.4 Performance Awareness
- Leverage compile-time macros for repetitive patterns.
- Use `Crystal::Printf` or `IO::Buffer` for efficient I/O.
- Avoid unnecessary object allocations when possible.
- Recognize when to use fibers vs synchronous execution for performance.

### 12.5 Code Organization and Design
- Encourage small, reusable, typed methods.
- Use modules for mixins and shared behavior.
- Prefer abstract classes or interfaces for polymorphic design.
- Apply union types for flexible, type-safe APIs.

### 12.6 Examples and Patterns
- Provide idiomatic examples of collection manipulation, concurrency patterns, and macros.
- Include both Ruby-equivalent examples and optimized Crystal implementations.
- Reinforce patterns that prevent common pitfalls in Crystal (e.g., nil access, type mismatches, concurrency bugs).

---

This expanded guide equips an LLM to reason deeply about **idiomatic, safe, and high-performance Crystal code**, producing outputs suitable for professional use while leveraging Ruby familiarity.

