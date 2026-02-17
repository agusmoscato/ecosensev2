defmodule EcosenseWeb.SensorController do
  use EcosenseWeb, :controller

  require Logger

  alias Ecosense.Repo

  # GET /api/sensors — lista todos los sensores (excluye soft-deleted)
  def index(conn, _params) do
    sensors =
      if repo_available?() do
        case fetch_sensors_from_db() do
          {:ok, rows} ->
            Logger.info("GET /api/sensors: #{length(rows)} sensores desde la base de datos")
            rows

          {:error, reason} ->
            Logger.warning("GET /api/sensors: Error BD: #{inspect(reason)}")
            []
        end
      else
        Logger.warning("GET /api/sensors: Repo no disponible")
        []
      end

    json(conn, sensors)
  end

  # POST /api/sensors — crea un sensor (type requerido; description, node_id, unit opcionales)
  def create(conn, params) do
    if repo_available?() do
      case create_sensor_in_db(params) do
        {:ok, sensor} ->
          conn
          |> put_status(:created)
          |> json(sensor)

        {:error, :invalid} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "El campo type es requerido."})

        {:error, reason} ->
          Logger.error("Create sensor failed: #{inspect(reason)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No se pudo crear el sensor."})
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Base de datos no disponible."})
    end
  end

  # PUT /api/sensors/:id — actualiza un sensor existente
  def update(conn, %{"id" => id} = params) do
    if repo_available?() do
      case update_sensor_in_db(id, params) do
        {:ok, sensor} ->
          json(conn, sensor)

        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Sensor no encontrado."})

        {:error, reason} ->
          Logger.error("Update sensor failed: #{inspect(reason)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "No se pudo actualizar el sensor.",
            reason: inspect(reason)
          })
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Base de datos no disponible."})
    end
  end

  # DELETE /api/sensors/:id — soft delete (pone fecha en deleted_at)
  def delete(conn, %{"id" => id}) do
    if repo_available?() do
      case soft_delete_sensor_in_db(id) do
        :ok ->
          conn
          |> put_status(:ok)
          |> json(%{message: "El sensor se eliminó correctamente."})

        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Sensor no encontrado o ya fue eliminado."})
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Base de datos no disponible."})
    end
  end

  defp repo_available? do
    case Process.whereis(Ecosense.Repo) do
      nil -> false
      _pid -> true
    end
  end

  defp fetch_sensors_from_db do
    try do
      query = "SELECT * FROM sensors WHERE deleted_at IS NULL ORDER BY id"

      case Repo.query(query) do
        {:ok, %MyXQL.Result{columns: cols, rows: rows}} ->
          mapped =
            Enum.map(rows, fn row ->
              cols
              |> Enum.zip(row)
              |> Map.new()
              |> normalize_row_for_json()
            end)

          {:ok, mapped}

        {:error, reason} ->
          Logger.error("Database error (sensors): #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception fetching sensors from DB: #{inspect(e)}")
        {:error, e}
    end
  end

  defp fetch_sensor_by_id(id) do
    query = "SELECT * FROM sensors WHERE id = ? AND deleted_at IS NULL"

    case Repo.query(query, [id]) do
      {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
        {:ok, cols |> Enum.zip(row) |> Map.new() |> normalize_row_for_json()}

      _ ->
        :not_found
    end
  end

  defp create_sensor_in_db(params) do
    type = params["type"] || params[:type]

    if type == nil or type == "" do
      {:error, :invalid}
    else
      try do
        description = params["description"] || params[:description] || ""
        node_id = params["node_id"] || params[:node_id] || 1
        node_id = if is_binary(node_id), do: String.to_integer(node_id), else: node_id
        unit = params["unit"] || params[:unit] || ""

        query = """
        INSERT INTO sensors (description, node_id, type, unit) VALUES (?, ?, ?, ?)
        """

        case Repo.query(query, [to_string(description), node_id, to_string(type), to_string(unit)]) do
          {:ok, _result} ->
            case Repo.query("SELECT * FROM sensors WHERE id = LAST_INSERT_ID()") do
              {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
                row_map = cols |> Enum.zip(row) |> Map.new() |> normalize_row_for_json()
                Logger.info("Sensor created, id=#{row_map["id"]}")
                {:ok, row_map}

              _ ->
                {:ok,
                 %{
                   "description" => description,
                   "node_id" => node_id,
                   "type" => type,
                   "unit" => unit
                 }}
            end

          {:error, reason} ->
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("Exception creating sensor: #{inspect(e)}")
          {:error, e}
      end
    end
  end

  defp update_sensor_in_db(id_str, params) do
    id = String.to_integer(id_str)

    # Verificamos que el sensor exista (y no esté soft-deleted)
    case fetch_sensor_by_id(id) do
      :not_found ->
        :not_found

      {:ok, _existing} ->
        type = params["type"] || params[:type]
        description = params["description"] || params[:description]
        node_id_raw = params["node_id"] || params[:node_id]
        unit = params["unit"] || params[:unit]

        node_id =
          cond do
            is_nil(node_id_raw) -> nil
            is_binary(node_id_raw) -> String.to_integer(node_id_raw)
            true -> node_id_raw
          end

        fields =
          Enum.filter(
            [
              {"type", type},
              {"description", description},
              {"node_id", node_id},
              {"unit", unit}
            ],
            fn {_k, v} -> v != nil end
          )

        if fields == [] do
          {:error, :empty}
        else
          set_clause =
            fields
            |> Enum.map(fn {k, _} -> "#{k} = ?" end)
            |> Enum.join(", ")

          values = Enum.map(fields, fn {_, v} -> v end)

          query = """
          UPDATE sensors
          SET #{set_clause}
          WHERE id = ? AND deleted_at IS NULL
          """

          case Repo.query(query, values ++ [id]) do
            {:ok, _} -> fetch_sensor_by_id(id)
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  defp soft_delete_sensor_in_db(id_str) do
    try do
      id = String.to_integer(id_str)

      query =
        "UPDATE sensors SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND deleted_at IS NULL"

      case Repo.query(query, [id]) do
        {:ok, %MyXQL.Result{num_rows: 1}} ->
          Logger.info("Sensor id=#{id} soft deleted")
          :ok

        {:ok, _} ->
          :not_found

        {:error, _reason} ->
          :not_found
      end
    rescue
      ArgumentError -> :not_found
      _e -> :not_found
    end
  end

  defp normalize_row_for_json(row) when is_map(row) do
    row
    |> Enum.map(fn
      {k, %NaiveDateTime{} = dt} -> {key_to_string(k), NaiveDateTime.to_iso8601(dt) <> "Z"}
      {k, %DateTime{} = dt} -> {key_to_string(k), DateTime.to_iso8601(dt)}
      {k, v} -> {key_to_string(k), v}
    end)
    |> Map.new()
  end

  defp key_to_string(k) when is_atom(k), do: to_string(k)
  defp key_to_string(k), do: k
end
