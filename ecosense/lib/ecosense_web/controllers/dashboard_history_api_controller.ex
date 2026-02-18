defmodule EcosenseWeb.DashboardHistoryApiController do
  @moduledoc """
  API para datos históricos agregados por sensor.
  GET /api/dashboard/history?node_id=1&sensor_id=1&from=2025-01-01T00:00:00Z&to=2025-01-31T23:59:59Z
  """
  use EcosenseWeb, :controller

  require Logger
  alias Ecosense.Repo

  def show(conn, params) do
    with {:ok, %{node_id: node_id, sensor_id: sensor_id, from: from, to: to}} <-
           validate_params(params),
         {:ok, node} <- fetch_node(node_id),
         {:ok, sensor} <- fetch_sensor_belonging_to_node(sensor_id, node_id),
         {:ok, result} <- fetch_aggregated_history(sensor_id, from, to) do
      json(conn, build_response(node, sensor, from, to, result))
    else
      {:error, :missing_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Parámetros requeridos: node_id, sensor_id, from, to (ISO8601)"})

      {:error, :node_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Nodo no encontrado"})

      {:error, :sensor_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sensor no encontrado o no pertenece al nodo"})

      {:error, reason} ->
        Logger.error("DashboardHistoryApiController error: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Error al cargar los datos históricos"})
    end
  end

  defp validate_params(params) do
    node_id = params["node_id"]
    sensor_id = params["sensor_id"]
    from_str = params["from"]
    to_str = params["to"]

    if blank?(node_id) or blank?(sensor_id) or blank?(from_str) or blank?(to_str) do
      {:error, :missing_params}
    else
      with {:ok, from} <- parse_iso8601(from_str),
           {:ok, to} <- parse_iso8601(to_str),
           {nid, _} <- Integer.parse(to_string(node_id)),
           {sid, _} <- Integer.parse(to_string(sensor_id)) do
        {:ok, %{node_id: nid, sensor_id: sid, from: from, to: to}}
      else
        _ -> {:error, :missing_params}
      end
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp parse_iso8601(str) when is_binary(str) do
    case NaiveDateTime.from_iso8601(String.replace(str, "Z", "")) do
      {:ok, dt} -> {:ok, dt}
      {:error, _} -> {:error, :invalid}
    end
  end

  defp parse_iso8601(_), do: {:error, :invalid}

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

  defp fetch_sensor_belonging_to_node(sensor_id, node_id) do
    query =
      "SELECT id, type, unit FROM sensors WHERE id = ? AND node_id = ? AND deleted_at IS NULL LIMIT 1"

    case Repo.query(query, [sensor_id, node_id]) do
      {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
        {:ok, row_to_map(cols, row)}

      {:ok, _} ->
        {:error, :sensor_not_found}

      {:error, _} ->
        {:error, :sensor_not_found}
    end
  end

  defp fetch_aggregated_history(sensor_id, from_dt, to_dt) do
    from_str = naive_to_mysql(from_dt)
    to_str = naive_to_mysql(to_dt)
    from_date = NaiveDateTime.to_date(from_dt)
    to_date = NaiveDateTime.to_date(to_dt)
    days = Date.diff(to_date, from_date)
    grouped_by = grouping_for_days(days)

    {period_expr, period_fmt} = period_expression(grouped_by)

    # Query agregada
    agg_query = """
    SELECT
      #{period_expr} AS period,
      AVG(value) AS value,
      MIN(value) AS min_val,
      MAX(value) AS max_val
    FROM readings
    WHERE sensor_id = ?
      AND timestamp BETWEEN ? AND ?
      AND deleted_at IS NULL
    GROUP BY #{period_expr}
    ORDER BY period ASC
    """

    # KPIs: current (último reading), average, min, max, last_reading_at
    kpi_query = """
    SELECT
      (SELECT value FROM readings
       WHERE sensor_id = ? AND timestamp BETWEEN ? AND ? AND deleted_at IS NULL
       ORDER BY timestamp DESC LIMIT 1) AS current_val,
      (SELECT timestamp FROM readings
       WHERE sensor_id = ? AND deleted_at IS NULL
       ORDER BY timestamp DESC LIMIT 1) AS last_reading_at,
      AVG(value) AS avg_val,
      MIN(value) AS min_val,
      MAX(value) AS max_val
    FROM readings
    WHERE sensor_id = ?
      AND timestamp BETWEEN ? AND ?
      AND deleted_at IS NULL
    """

    with {:ok, %MyXQL.Result{columns: agg_cols, rows: agg_rows}} <-
           Repo.query(agg_query, [sensor_id, from_str, to_str]),
         {:ok, %MyXQL.Result{columns: kpi_cols, rows: kpi_rows}} <-
           Repo.query(kpi_query, [
             sensor_id, from_str, to_str,
             sensor_id,
             sensor_id, from_str, to_str
           ]) do
      data =
        Enum.map(agg_rows, fn row ->
          map = row_to_map(agg_cols, row)
          period = format_period_iso8601(map["period"], period_fmt)
          %{
            "period" => period,
            "value" => round_float(map["value"])
          }
        end)

      {kpi, last_reading_at} =
        if kpi_rows != [] do
          m = row_to_map(kpi_cols, hd(kpi_rows))
          kpi_map = %{
            "current" => round_float(m["current_val"]),
            "average" => round_float(m["avg_val"]),
            "min" => round_float(m["min_val"]),
            "max" => round_float(m["max_val"])
          }
          last_ts = format_timestamp_iso8601(m["last_reading_at"])
          {kpi_map, last_ts}
        else
          {%{"current" => nil, "average" => nil, "min" => nil, "max" => nil}, nil}
        end

      {:ok,
       %{
         data: data,
         kpis: kpi,
         grouped_by: grouped_by,
         last_reading_at: last_reading_at
       }}
    else
      {:error, _} = err -> err
      e -> {:error, e}
    end
  end

  defp grouping_for_days(days) when days <= 2, do: "hour"
  defp grouping_for_days(days) when days <= 60, do: "day"
  defp grouping_for_days(days) when days <= 180, do: "week"
  defp grouping_for_days(_), do: "month"

  # MySQL no tiene date_trunc; usamos expresiones equivalentes
  defp period_expression("hour") do
    {"DATE_FORMAT(timestamp, '%Y-%m-%d %H:00:00')", :datetime}
  end

  defp period_expression("day") do
    {"DATE(timestamp)", :date}
  end

  defp period_expression("week") do
    {"DATE_SUB(DATE(timestamp), INTERVAL WEEKDAY(timestamp) DAY)", :date}
  end

  defp period_expression("month") do
    {"DATE_FORMAT(timestamp, '%Y-%m-01')", :date}
  end

  defp format_period_iso8601(nil, _), do: nil

  defp format_period_iso8601(%NaiveDateTime{} = dt, _), do: NaiveDateTime.to_iso8601(dt) <> "Z"

  defp format_period_iso8601(%DateTime{} = dt, _), do: DateTime.to_iso8601(dt)

  defp format_period_iso8601(%Date{} = d, _), do: Date.to_iso8601(d) <> "T00:00:00Z"

  defp format_period_iso8601(val, :datetime) when is_binary(val) do
    # MySQL 'YYYY-MM-DD HH:MM:SS' -> ISO8601
    String.replace(val, " ", "T") <> "Z"
  end

  defp format_period_iso8601(val, :date) when is_binary(val) do
    # MySQL 'YYYY-MM-DD' -> ISO8601
    val <> "T00:00:00Z"
  end

  defp format_period_iso8601(val, _) when is_binary(val) do
    if String.contains?(val, " ") do
      String.replace(val, " ", "T") <> "Z"
    else
      val <> "T00:00:00Z"
    end
  end

  defp format_period_iso8601(val, _), do: to_string(val)

  defp format_timestamp_iso8601(nil), do: nil

  defp format_timestamp_iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  defp format_timestamp_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp format_timestamp_iso8601(val) when is_binary(val) do
    if String.contains?(val, " ") do
      String.replace(val, " ", "T") <> "Z"
    else
      val <> "T00:00:00Z"
    end
  end

  defp format_timestamp_iso8601(_), do: nil

  defp naive_to_mysql(%NaiveDateTime{} = dt) do
    NaiveDateTime.to_string(dt) |> String.replace("T", " ") |> String.slice(0..18)
  end

  defp round_float(nil), do: nil
  defp round_float(%Decimal{} = v), do: v |> Decimal.to_float() |> Float.round(2)
  defp round_float(v) when is_number(v), do: Float.round(v, 2)
  defp round_float(v), do: v

  defp build_response(node, sensor, from, to, %{
         data: data,
         kpis: kpis,
         grouped_by: grouped_by,
         last_reading_at: last_reading_at
       }) do
    from_iso = NaiveDateTime.to_iso8601(from) <> "Z"
    to_iso = NaiveDateTime.to_iso8601(to) <> "Z"

    %{
      "node" => normalize_node(node),
      "sensor" => %{
        "id" => sensor["id"],
        "type" => sensor["type"],
        "unit" => sensor["unit"],
        "last_reading_at" => last_reading_at
      },
      "range" => %{
        "from" => from_iso,
        "to" => to_iso,
        "grouped_by" => grouped_by
      },
      "kpis" => kpis,
      "data" => data
    }
  end

  defp normalize_node(node) when is_map(node) do
    node
    |> Enum.map(fn
      {k, %NaiveDateTime{} = dt} -> {key_str(k), NaiveDateTime.to_iso8601(dt) <> "Z"}
      {k, %DateTime{} = dt} -> {key_str(k), DateTime.to_iso8601(dt)}
      {k, v} -> {key_str(k), v}
    end)
    |> Map.new()
  end

  defp key_str(k) when is_atom(k), do: to_string(k)
  defp key_str(k), do: to_string(k)

  defp row_to_map(cols, row) do
    cols
    |> Enum.map(&key_str/1)
    |> Enum.zip(row)
    |> Map.new()
  end
end
