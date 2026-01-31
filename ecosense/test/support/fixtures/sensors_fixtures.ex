defmodule Ecosense.SensorsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ecosense.Sensors` context.
  """

  @doc """
  Generate a reading.
  """
  def reading_fixture(attrs \\ %{}) do
    {:ok, reading} =
      attrs
      |> Enum.into(%{
        humidity: 120.5,
        temperature: 120.5
      })
      |> Ecosense.Sensors.create_reading()

    reading
  end
end
