defmodule PropWise.FunctionInfo do
  @moduledoc """
  Represents metadata about a parsed function definition.
  """

  @type t :: %__MODULE__{
          module: String.t(),
          name: atom(),
          arity: non_neg_integer(),
          args: list(),
          body: Macro.t(),
          file: String.t(),
          line: pos_integer(),
          type: :public | :private
        }

  @enforce_keys [:module, :name, :arity, :args, :body, :file, :line, :type]
  defstruct [:module, :name, :arity, :args, :body, :file, :line, :type]
end
