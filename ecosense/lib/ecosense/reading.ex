defmodule Ecosense.Reading do
  use Ecto.Schema
  import Ecto.Changeset

  schema "readings" do
    field :temperature, :float
    field :humidity, :float

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reading, attrs) do
    reading
    |> cast(attrs, [:temperature, :humidity])
    |> validate_required([:temperature, :humidity])
  end
end
