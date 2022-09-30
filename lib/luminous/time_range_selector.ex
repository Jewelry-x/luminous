defmodule Luminous.TimeRangeSelector do
  @moduledoc """
  a selector represents the widget in the dashboard that
  allows for selecting a time range/period

  it is defined at compile time and populated at compile time (current
  value)

  it can also be updated with a new value

  """
  alias Luminous.TimeRange

  @doc """
  this behaviour needs to be implemented by the module
  that is passed to define/2
  """
  @callback default_time_range(time_zone()) :: TimeRange.t()

  @type time_zone :: binary()

  @type t :: %__MODULE__{
          mod: module(),
          hook: binary(),
          id: binary(),
          current_time_range: nil | TimeRange.t()
        }

  @enforce_keys [:mod]
  defstruct [:mod, :hook, :id, :current_time_range]

  @spec populate(t(), time_zone()) :: t()
  def populate(selector, time_zone) do
    Map.put(selector, :current_time_range, default_time_range(selector, time_zone))
  end

  @spec define(module(), Keyword.t()) :: t()
  def define(mod, opts \\ []) do
    %__MODULE__{
      mod: mod,
      hook: Keyword.get(opts, :hook, "TimeRangeHook"),
      id: Keyword.get(opts, :id, "time-range-selector")
    }
  end

  @spec default_time_range(t(), time_zone()) :: TimeRange.t()
  def default_time_range(selector, time_zone) do
    apply(selector.mod, :default_time_range, [time_zone])
  end

  @spec update_current(t(), TimeRange.t()) :: t()
  def update_current(selector, time_range) do
    Map.put(selector, :current_time_range, time_range)
  end
end
