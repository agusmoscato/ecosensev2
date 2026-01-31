defmodule Ecosense.Repo.Migrations.CreateReadings do
  use Ecto.Migration

  def change do
    create table(:readings) do
      add :temperature, :float
      add :humidity, :float

      timestamps(type: :utc_datetime)
    end
  end
end
