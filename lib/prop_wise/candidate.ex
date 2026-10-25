defmodule PropWise.Candidate do
  @moduledoc """
  Represents a scored property-based testing candidate.
  """

  @typedoc """
  Purity classification: `:pure` (all calls resolved and side-effect free),
  `:unknown` (no side effect found, but some calls could not be resolved) or
  `:impure` (a known side effect was found).
  """
  @type purity :: :pure | :unknown | :impure

  @type side_effect :: PropWise.PurityAnalyzer.side_effect()

  @type pattern :: {pattern_type(), String.t()}

  @type pattern_type ::
          :collection_operation
          | :transformation
          | :validation
          | :algebraic
          | :encoder_decoder
          | :parser
          | :numeric

  @type law :: PropWise.LawTable.law()

  @type t :: %__MODULE__{
          module: String.t(),
          name: atom() | String.t(),
          arity: non_neg_integer(),
          file: String.t(),
          line: pos_integer(),
          type: :public | :private,
          purity: purity(),
          side_effects: [side_effect()],
          unresolved_calls: [String.t()],
          patterns: [pattern()],
          laws: [law()],
          score: non_neg_integer(),
          rank: pos_integer(),
          inverse_pair: boolean(),
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
    :rank,
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
    :rank,
    :suggestions,
    side_effects: [],
    unresolved_calls: [],
    laws: [],
    inverse_pair: false
  ]
end
