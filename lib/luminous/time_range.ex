defmodule Luminous.TimeRange do
  @moduledoc """
  This module defines a struct with two fields (`:from` and `:to`) to represent a time range.
  Additionally, various helper functions are defined that operate on time ranges.
  """

  @type t() :: %__MODULE__{from: DateTime.t(), to: DateTime.t()}

  defstruct [:from, :to]

  @spec new(DateTime.t(), DateTime.t()) :: t()
  def new(from, to), do: %__MODULE__{from: from, to: to}

  @spec from_iso(binary(), binary()) :: t()
  def from_iso(from_iso, to_iso) do
    [from, to] =
      Enum.map([from_iso, to_iso], fn iso ->
        {:ok, dt, _} = DateTime.from_iso8601(iso)
        dt
      end)

    new(from, to)
  end

  @spec from_unix(non_neg_integer(), non_neg_integer()) :: t()
  def from_unix(from_unix, to_unix) do
    [from, to] =
      Enum.map([from_unix, to_unix], fn ut ->
        DateTime.from_unix!(ut)
      end)

    new(from, to)
  end

  @spec to_map(t()) :: map()
  def to_map(time_range), do: Map.from_struct(time_range)

  @spec shift_zone!(t(), binary()) :: t()
  def shift_zone!(time_range, time_zone) do
    new(
      DateTime.shift_zone!(time_range.from, time_zone),
      DateTime.shift_zone!(time_range.to, time_zone)
    )
  end

  @spec today(binary(), DateTime.t() | nil) :: t()
  def today(tz, now \\ nil) do
    now = now || DateTime.now!(tz)
    from = round(now, :day)
    to = now |> add(1, :day) |> round(:day) |> add(-1, :second)
    new(from, to)
  end

  @spec yesterday(binary(), DateTime.t() | nil) :: t()
  def yesterday(tz, now \\ nil) do
    now = now || DateTime.now!(tz)
    to = now |> round(:day) |> add(-1, :second)
    from = now |> add(-1, :day) |> round(:day)
    new(from, to)
  end

  @spec tomorrow(binary(), DateTime.t() | nil) :: t()
  def tomorrow(tz, now \\ nil) do
    now = now || DateTime.now!(tz)
    from = now |> add(1, :day) |> round(:day)
    to = now |> add(2, :day) |> round(:day) |> add(-1, :second)
    new(from, to)
  end

  @spec last_n_days(non_neg_integer(), binary(), DateTime.t() | nil) :: t()
  def last_n_days(n, tz, now \\ nil) do
    now = now || DateTime.now!(tz)
    to = now |> round(:day) |> add(1, :day) |> add(-1, :second)
    from = now |> add(1 - n, :day) |> round(:day)
    new(from, to)
  end

  @spec this_week(binary(), DateTime.t() | nil) :: t()
  def this_week(tz, now \\ nil) do
    today = DateTime.to_date(now || DateTime.now!(tz))
    from = today |> Date.beginning_of_week() |> DateTime.new!(~T[00:00:00], tz)
    to = today |> Date.end_of_week() |> DateTime.new!(~T[23:59:59], tz)
    new(from, to)
  end

  @spec last_week(binary(), DateTime.t() | nil) :: t()
  def last_week(tz, now \\ nil) do
    same_day_last_week = (now || DateTime.now!(tz)) |> DateTime.to_date() |> Date.add(-7)
    from = same_day_last_week |> Date.beginning_of_week() |> DateTime.new!(~T[00:00:00], tz)
    to = same_day_last_week |> Date.end_of_week() |> DateTime.new!(~T[23:59:59], tz)
    new(from, to)
  end

  @spec this_month(binary(), DateTime.t() | nil) :: t()
  def this_month(tz, now \\ nil) do
    now = now || DateTime.now!(tz)
    from = round(now, :month)
    to = now |> add(1, :month) |> round(:month) |> add(-1, :second)
    new(from, to)
  end

  @spec last_month(binary(), DateTime.t() | nil) :: t()
  def last_month(tz, now \\ nil) do
    now = now || DateTime.now!(tz)
    to = now |> round(:month) |> add(-1, :second)
    from = now |> add(-1, :month) |> round(:month)
    new(from, to)
  end

  @spec round(DateTime.t(), atom()) :: DateTime.t()
  def round(dt, :day) do
    start_of_day = Time.new!(0, 0, 0)
    DateTime.new!(DateTime.to_date(dt), start_of_day, dt.time_zone)
  end

  def round(dt, :week) do
    start_of_day = Time.new!(0, 0, 0)
    start_of_week = Date.beginning_of_week(dt)
    DateTime.new!(start_of_week, start_of_day, dt.time_zone)
  end

  def round(dt, :month) do
    start_of_day = Time.new!(0, 0, 0)
    start_of_month = Date.beginning_of_month(dt)
    DateTime.new!(start_of_month, start_of_day, dt.time_zone)
  end

  @spec add(DateTime.t(), integer(), atom()) :: DateTime.t()
  def add(dt, n, :second) do
    DateTime.add(dt, n, :second)
  end

  def add(dt, n, :minute) do
    DateTime.add(dt, n * 60, :second)
  end

  def add(dt, n, :hour), do: add(dt, n * 60, :minute)
  def add(dt, n, :day), do: add(dt, 24 * n, :hour)

  def add(%DateTime{:year => year, :month => month} = dt, n, :month) do
    m = month + n

    shifted =
      cond do
        m > 0 ->
          years = div(m - 1, 12)
          month = rem(m - 1, 12) + 1
          %{dt | :year => year + years, :month => month}

        m <= 0 ->
          years = div(m, 12) - 1
          month = 12 + rem(m, 12)
          %{dt | :year => year + years, :month => month}
      end

    # If the shift fails, it's because it's a high day number, and the month
    # shifted to does not have that many days. This will be handled by always
    # shifting to the last day of the month shifted to.
    case :calendar.valid_date({shifted.year, shifted.month, shifted.day}) do
      false ->
        last_day = :calendar.last_day_of_the_month(shifted.year, shifted.month)

        cond do
          shifted.day <= last_day ->
            shifted

          :else ->
            %{shifted | :day => last_day}
        end

      true ->
        shifted
    end
  end
end
