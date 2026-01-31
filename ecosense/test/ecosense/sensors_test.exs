defmodule Ecosense.SensorsTest do
  use Ecosense.DataCase

  alias Ecosense.Sensors

  describe "readings" do
    alias Ecosense.Sensors.Reading

    import Ecosense.SensorsFixtures

    @invalid_attrs %{temperature: nil, humidity: nil}

    test "list_readings/0 returns all readings" do
      reading = reading_fixture()
      assert Sensors.list_readings() == [reading]
    end

    test "get_reading!/1 returns the reading with given id" do
      reading = reading_fixture()
      assert Sensors.get_reading!(reading.id) == reading
    end

    test "create_reading/1 with valid data creates a reading" do
      valid_attrs = %{temperature: 120.5, humidity: 120.5}

      assert {:ok, %Reading{} = reading} = Sensors.create_reading(valid_attrs)
      assert reading.temperature == 120.5
      assert reading.humidity == 120.5
    end

    test "create_reading/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Sensors.create_reading(@invalid_attrs)
    end

    test "update_reading/2 with valid data updates the reading" do
      reading = reading_fixture()
      update_attrs = %{temperature: 456.7, humidity: 456.7}

      assert {:ok, %Reading{} = reading} = Sensors.update_reading(reading, update_attrs)
      assert reading.temperature == 456.7
      assert reading.humidity == 456.7
    end

    test "update_reading/2 with invalid data returns error changeset" do
      reading = reading_fixture()
      assert {:error, %Ecto.Changeset{}} = Sensors.update_reading(reading, @invalid_attrs)
      assert reading == Sensors.get_reading!(reading.id)
    end

    test "delete_reading/1 deletes the reading" do
      reading = reading_fixture()
      assert {:ok, %Reading{}} = Sensors.delete_reading(reading)
      assert_raise Ecto.NoResultsError, fn -> Sensors.get_reading!(reading.id) end
    end

    test "change_reading/1 returns a reading changeset" do
      reading = reading_fixture()
      assert %Ecto.Changeset{} = Sensors.change_reading(reading)
    end
  end
end
