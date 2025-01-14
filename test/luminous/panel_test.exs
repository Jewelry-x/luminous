defmodule Luminous.PanelTest do
  use ExUnit.Case

  alias Luminous.Panel
  alias Luminous.Query
  alias Luminous.Query.Attributes

  defmodule ChartQueries do
    @behaviour Query
    @impl true
    def query(:normal, _time_range, _variables) do
      [
        %{:time => ~U[2022-08-03T00:00:00Z], :l1 => 1, :l2 => 11, "l3" => 111},
        %{:time => ~U[2022-08-04T00:00:00Z], :l1 => 2, :l2 => 12, "l3" => 112}
      ]
      |> Query.Result.new()
    end

    def query(:sparse, _time_range, _variables) do
      [
        %{:time => ~U[2022-08-03T00:00:00Z], :l1 => 1, "l3" => 111},
        %{:time => ~U[2022-08-04T00:00:00Z], :l2 => 12, "l3" => 112}
      ]
      |> Query.Result.new(
        attrs: %{
          "l1" => Attributes.define(type: :bar, order: 0),
          "l2" => Attributes.define(order: 1),
          "l3" => Attributes.define(type: :bar, order: 2)
        }
      )
    end

    def query(:null, _time_range, _variables) do
      Query.Result.new([
        [{:time, ~U[2022-08-03T00:00:00Z]}, {:l1, 1}, {:l2, nil}]
      ])
    end
  end

  defmodule StatQueries do
    @behaviour Query
    @impl true
    def query(:single_stat, _time_range, _variables), do: Query.Result.new(%{"foo" => 666})

    def query(:multiple_stats, _time_range, _variables) do
      Query.Result.new(%{"foo" => 11, "bar" => 13},
        attrs: %{"foo" => Attributes.define(title: "Foo", unit: "mckk")}
      )
    end
  end

  describe "Chart Panel" do
    test "fetches and transforms the data from the actual query" do
      results =
        :normal
        |> Query.define(ChartQueries)
        |> Query.execute(nil, [])
        |> Panel.Chart.transform()

      t1 = DateTime.to_unix(~U[2022-08-03T00:00:00Z], :millisecond)
      t2 = DateTime.to_unix(~U[2022-08-04T00:00:00Z], :millisecond)

      expected_results = [
        %{
          rows: [%{x: t1, y: Decimal.new(1)}, %{x: t2, y: Decimal.new(2)}],
          label: "l1",
          attrs: Attributes.define(),
          stats: %{
            avg: Decimal.new(2),
            label: "l1",
            max: Decimal.new(2),
            min: Decimal.new(1),
            n: 2,
            sum: Decimal.new(3)
          }
        },
        %{
          rows: [%{x: t1, y: Decimal.new(11)}, %{x: t2, y: Decimal.new(12)}],
          label: "l2",
          attrs: Attributes.define(),
          stats: %{
            avg: Decimal.new(12),
            label: "l2",
            max: Decimal.new(12),
            min: Decimal.new(11),
            n: 2,
            sum: Decimal.new(23)
          }
        },
        %{
          rows: [%{x: t1, y: Decimal.new(111)}, %{x: t2, y: Decimal.new(112)}],
          label: "l3",
          attrs: Attributes.define(),
          stats: %{
            avg: Decimal.new(112),
            label: "l3",
            max: Decimal.new(112),
            min: Decimal.new(111),
            n: 2,
            sum: Decimal.new(223)
          }
        }
      ]

      assert ^expected_results = results
    end

    test "can fetch and transform sparse data from the query" do
      results =
        :sparse
        |> Query.define(ChartQueries)
        |> Query.execute(nil, [])
        |> Panel.Chart.transform()

      t1 = DateTime.to_unix(~U[2022-08-03T00:00:00Z], :millisecond)
      t2 = DateTime.to_unix(~U[2022-08-04T00:00:00Z], :millisecond)

      expected_d1 = [%{x: t1, y: Decimal.new(1)}]
      expected_d2 = [%{x: t2, y: Decimal.new(12)}]
      expected_d3 = [%{x: t1, y: Decimal.new(111)}, %{x: t2, y: Decimal.new(112)}]

      expected_attrs_1 = Attributes.define(type: :bar, order: 0)
      expected_attrs_2 = Attributes.define(order: 1)
      expected_attrs_3 = Attributes.define(type: :bar, order: 2)

      assert [
               %{
                 rows: ^expected_d1,
                 label: "l1",
                 attrs: ^expected_attrs_1
               },
               %{
                 rows: ^expected_d2,
                 label: "l2",
                 attrs: ^expected_attrs_2
               },
               %{
                 rows: ^expected_d3,
                 label: "l3",
                 attrs: ^expected_attrs_3
               }
             ] = results
    end

    test "can fetch and transform query results that contain nil" do
      results =
        :null
        |> Query.define(ChartQueries)
        |> Query.execute(nil, [])
        |> Panel.Chart.transform()

      t = DateTime.to_unix(~U[2022-08-03T00:00:00Z], :millisecond)

      expected_d1 = [%{x: t, y: Decimal.new(1)}]
      expected_d2 = []

      assert [
               %{
                 rows: ^expected_d1,
                 label: "l1"
               },
               %{
                 rows: ^expected_d2,
                 label: "l2"
               }
             ] = results
    end
  end

  describe "Chart Statistics" do
    test "calculates the basic statistics" do
      ds = [%{y: Decimal.new(1)}, %{y: Decimal.new(3)}, %{y: Decimal.new(-2)}]

      assert %{label: "foo", n: 3, min: min, max: max, avg: avg, sum: sum} =
               Panel.Chart.statistics(ds, "foo")

      assert min == Decimal.new(-2)
      assert max == Decimal.new(3)
      assert avg == Decimal.new(1)
      assert sum == Decimal.new(2)
    end

    test "rounds the average acc. to the max number of decimal digits in the dataset" do
      ds = [%{y: Decimal.new("1.234")}, %{y: Decimal.new("1.11")}]

      assert %{avg: avg, sum: sum} = Panel.Chart.statistics(ds, "foo")
      assert avg == Decimal.new("1.172")
      assert sum == Decimal.new("2.344")
    end

    test "can handle an empty dataset" do
      assert %{n: 0, avg: nil, sum: nil, min: nil, max: nil} = Panel.Chart.statistics([], "foo")
    end

    test "can handle datasets that contain nils" do
      ds = [
        %{y: Decimal.new(4)},
        %{y: nil},
        %{y: Decimal.new(3)},
        %{y: Decimal.new(5)},
        %{y: nil}
      ]

      assert %{n: 3, avg: avg, sum: sum, min: min, max: max} = Panel.Chart.statistics(ds, "foo")
      assert min == Decimal.new(3)
      assert max == Decimal.new(5)
      assert sum == Decimal.new(12)
      assert avg == Decimal.new(4)
    end

    test "can handle datasets with nils only" do
      ds = [%{y: nil}, %{y: nil}]
      assert %{n: 0, avg: nil, sum: nil, min: nil, max: nil} = Panel.Chart.statistics(ds, "foo")
    end
  end

  describe "Stat Panel" do
    test "single stat" do
      assert [result | []] =
               :single_stat
               |> Query.define(StatQueries)
               |> Query.execute(nil, [])
               |> Panel.Stat.transform()

      assert %{title: nil, unit: nil, value: 666} = result
    end

    test "multiple stats" do
      results =
        :multiple_stats
        |> Query.define(StatQueries)
        |> Query.execute(nil, [])
        |> Panel.Stat.transform()

      assert [
               %{
                 title: nil,
                 unit: nil,
                 value: 13
               },
               %{
                 title: "Foo",
                 unit: "mckk",
                 value: 11
               }
             ] = results
    end
  end
end
