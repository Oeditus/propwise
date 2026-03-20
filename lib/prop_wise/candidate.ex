defmodule PropWise.Candidate do
  @moduledoc """
  Represents a scored property-based testing candidate.
  """

  @type purity :: {:pure, []} | {:impure, [side_effect()]}
  @type side_effect ::
          {:module_call, module(), atom(), non_neg_integer()}
          | {:function_call, atom(), non_neg_integer()}
          | {:receive_block}
  @type pattern :: {pattern_type(), String.t()}
  @type pattern_type ::
          :collection_operation
          | :transformation
          | :validation
          | :algebraic
          | :encoder_decoder
          | :parser
          | :numeric

  @type t :: %__MODULE__{
          module: String.t(),
          name: atom(),
          arity: non_neg_integer(),
          file: String.t(),
          line: pos_integer(),
          type: :public | :private,
          purity: purity(),
          patterns: [pattern()],
          score: non_neg_integer(),
          suggestions: [String.t()]
        }

  @enforce_keys [
    :module,
    :name,
    :arity,
    :file,
    :line,
    :type,
    :purity,
    :patterns,
    :score,
    :suggestions
  ]
  defstruct [
    :module,
    :name,
    :arity,
    :file,
    :line,
    :type,
    :purity,
    :patterns,
    :score,
    :suggestions
  ]
end
