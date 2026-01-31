defmodule EcosenseWeb.ReadingControllerTest do
  use EcosenseWeb.ConnCase

  import Ecosense.SensorsFixtures
  alias Ecosense.Sensors.Reading

  @create_attrs %{
    temperature: 120.5,
    humidity: 120.5
  }
  @update_attrs %{
    temperature: 456.7,
    humidity: 456.7
  }
  @invalid_attrs %{temperature: nil, humidity: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all readings", %{conn: conn} do
      conn = get(conn, ~p"/api/readings")
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create reading" do
    test "renders reading when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/readings", reading: @create_attrs)
      assert %{"id" => id} = json_response(conn, 201)["data"]

      conn = get(conn, ~p"/api/readings/#{id}")

      assert %{
               "id" => ^id,
               "humidity" => 120.5,
               "temperature" => 120.5
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/readings", reading: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update reading" do
    setup [:create_reading]

    test "renders reading when data is valid", %{conn: conn, reading: %Reading{id: id} = reading} do
      conn = put(conn, ~p"/api/readings/#{reading}", reading: @update_attrs)
      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, ~p"/api/readings/#{id}")

      assert %{
               "id" => ^id,
               "humidity" => 456.7,
               "temperature" => 456.7
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn, reading: reading} do
      conn = put(conn, ~p"/api/readings/#{reading}", reading: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete reading" do
    setup [:create_reading]

    test "deletes chosen reading", %{conn: conn, reading: reading} do
      conn = delete(conn, ~p"/api/readings/#{reading}")
      assert response(conn, 204)

      assert_error_sent 404, fn ->
        get(conn, ~p"/api/readings/#{reading}")
      end
    end
  end

  defp create_reading(_) do
    reading = reading_fixture()

    %{reading: reading}
  end
end
