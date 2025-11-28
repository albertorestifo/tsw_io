# Claude Code Instructions

Project-specific guidelines for Claude Code when working on this codebase.

First read and follow AGENTS.md, the following are additional constraints.

## Elixir Coding Guidelines

### Type Safety

1. **Always match structs in function arguments**: When a function accepts a struct, pattern match on the struct type. This aids Dialyzer type checking and makes the code more explicit.

   ```elixir
   # Good
   def process(%MyStruct{} = struct) do
     # ...
   end

   # Bad
   def process(struct) do
     # ...
   end
   ```

2. **Avoid untyped maps**: Prefer structs or well-defined map types over generic maps. When maps are necessary, document their expected shape or use typespecs.

   ```elixir
   # Good - use a struct
   defmodule Config do
     defstruct [:port, :timeout]
   end

   def connect(%Config{} = config), do: # ...

   # Good - if map is needed, document shape
   @type options :: %{port: integer(), timeout: integer()}
   @spec connect(options()) :: :ok
   def connect(options), do: # ...

   # Bad - untyped map
   def connect(config), do: # ...
   ```

### Protocol Messages

When defining protocol messages with enum-like fields, handle the atom-to-integer conversion directly in the encode/decode functions using binary pattern matching. This keeps the API clean (atoms) while maintaining efficient wire format (integers).

```elixir
# Good - atom in struct, conversion in encode/decode
defmodule MyMessage do
  defstruct [:type]  # type is an atom like :analog, :digital

  def encode(%__MODULE__{type: :analog}) do
    {:ok, <<0x01, 0x00>>}  # 0x00 = analog
  end

  def encode(%__MODULE__{type: :digital}) do
    {:ok, <<0x01, 0x01>>}  # 0x01 = digital
  end

  def decode(<<0x01, 0x00>>) do
    {:ok, %__MODULE__{type: :analog}}
  end

  def decode(<<0x01, 0x01>>) do
    {:ok, %__MODULE__{type: :digital}}
  end
end

# Bad - integer in struct, conversion elsewhere
defmodule MyMessage do
  defstruct [:type]  # type is 0 or 1

  def input_type_to_int(:analog), do: 0  # Don't do this
end
```
