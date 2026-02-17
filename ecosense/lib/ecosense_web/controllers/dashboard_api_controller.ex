defmodule EcosenseWeb.DashboardApiController do
  use EcosenseWeb, :controller

  require Logger

  alias Ecosense.Repo

  # GET /api/dashboard?node_id=1 — nodo, sensores del nodo y lecturas recientes de esos sensores
  def show(conn, params) do
    node_id = params["node_id"]

    if node_id == nil or node_id == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Se requiere el parámetro node_id."})
    else
      case fetch_dashboard_data(node_id) do
        {:ok, data} ->
          json(conn, data)

        {:error, :node_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Nodo no encontrado."})

        {:error, reason} ->
          Logger.error("Dashboard API error: #{inspect(reason)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Error al cargar los datos del dashboard."})
      end
    end
  end

  defp fetch_dashboard_data(node_id_str) do
    try do
      node_id = String.to_integer(node_id_str)

      with {:ok, node} <- fetch_node(node_id),
           {:ok, sensors} <- fetch_sensors_for_node(node_id),
           {:ok, readings} <- fetch_readings_for_sensors(sensors) do
        {:ok,
         %{
           node: node,
           sensors: sensors,
           readings: readings
         }}
      end
    rescue
      ArgumentError -> {:error, :node_not_found}
    end
  end

  defp fetch_node(node_id) do
    query = "SELECT * FROM nodes WHERE id = ? AND deleted_at IS NULL LIMIT 1"

    case Repo.query(query, [node_id]) do
      {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
        {:ok, row_to_map(cols, row)}

      {:ok, _} ->
        {:error, :node_not_found}

      {:error, _} ->
        {:error, :node_not_found}
    end
  end

  defp fetch_sensors_for_node(node_id) do
    query = "SELECT * FROM sensors WHERE node_id = ? AND deleted_at IS NULL ORDER BY id"

    case Repo.query(query, [node_id]) do
      {:ok, %MyXQL.Result{columns: cols, rows: rows}} ->
        sensors =
          Enum.map(rows, fn row ->
            row_to_map(cols, row) |> normalize_dates()
          end)

        {:ok, sensors}

      {:error, _} ->
        {:ok, []}
    end
  end

  defp fetch_readings_for_sensors(sensors) do
    if sensors == [] do
      {:ok, []}
    else
      ids = Enum.map(sensors, & &1["id"]) |> Enum.uniq()
      placeholders = Enum.map(ids, fn _ -> "?" end) |> Enum.join(", ")
      # Últimas lecturas para los sensores del nodo (ej. 200 más recientes)
      query = """
      SELECT * FROM readings
      WHERE sensor_id IN (#{placeholders}) AND deleted_at IS NULL
      ORDER BY timestamp DESC
      LIMIT 300
      """

      case Repo.query(query, ids) do
        {:ok, %MyXQL.Result{columns: cols, rows: rows}} ->
          readings =
            Enum.map(rows, fn row ->
              row_to_map(cols, row) |> normalize_dates()
            end)

          {:ok, readings}

        {:error, _} ->
          {:ok, []}
      end
    end
  end

  defp row_to_map(cols, row) do
    cols
    |> Enum.zip(row)
    |> Map.new()
  end

  defp normalize_dates(map) when is_map(map) do
    Enum.map(map, fn
      {k, %NaiveDateTime{} = dt} -> {key_str(k), NaiveDateTime.to_iso8601(dt) <> "Z"}
      {k, %DateTime{} = dt} -> {key_str(k), DateTime.to_iso8601(dt)}
      {k, v} -> {key_str(k), v}
    end)
    |> Map.new()
  end

  defp key_str(k) when is_atom(k), do: to_string(k)
  defp key_str(k), do: k
end
