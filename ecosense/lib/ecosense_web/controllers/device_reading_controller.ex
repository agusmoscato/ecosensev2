defmodule EcosenseWeb.DeviceReadingController do
  use EcosenseWeb, :controller

  require Logger

  alias Ecosense.{Repo, Processing, ReadingQueue}

  # POST /api/devices/readings — endpoint protegido para dispositivos IoT
  # Requiere header x-api-key. Las lecturas se encolan y se guardan en BD de forma asíncrona.
  def create(conn, params) do
    node = conn.assigns.current_node

    case validate_and_enqueue_reading(params, node) do
      :ok ->
        conn
        |> put_status(:accepted)
        |> json(%{message: "Lectura encolada correctamente"})

      {:error, :invalid_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Parámetros inválidos: se requiere sensor_id y value"})

      {:error, :sensor_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Sensor no encontrado o no pertenece a este nodo"})

      {:error, reason} ->
        Logger.error("Device reading creation failed: #{inspect(reason)}")
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No se pudo guardar la lectura"})
    end
  end

  defp validate_and_enqueue_reading(params, node) do
    sensor_id = params["sensor_id"] || params[:sensor_id]
    value = params["value"] || params[:value]

    cond do
      sensor_id == nil or value == nil ->
        {:error, :invalid_params}

      true ->
        case validate_sensor_belongs_to_node(sensor_id, node["id"]) do
          {:ok, _sensor} ->
            reading_params = %{
              "sensor_id" => sensor_id,
              "value" => value,
              "source" => params["source"] || params[:source] || "device"
            }

            case Processing.validate(reading_params) do
              :ok ->
                transformed = Processing.transform(reading_params)
                # Añadir node_id para actualizar last_seen en el worker
                enqueue_reading = Map.put(transformed, "node_id", node["id"])
                ReadingQueue.enqueue(enqueue_reading)
                :ok

              {:error, _msg} ->
                {:error, :invalid_params}
            end

          {:error, :not_found} ->
            {:error, :sensor_not_found}
        end
    end
  end

  # Verifica que el sensor exista, pertenezca al nodo, y que tanto el sensor como el nodo NO tengan deleted_at
  defp validate_sensor_belongs_to_node(sensor_id, node_id) do
    try do
      sensor_id_int = if is_binary(sensor_id), do: String.to_integer(sensor_id), else: sensor_id
      node_id_int = if is_binary(node_id), do: String.to_integer(node_id), else: node_id

      query = """
      SELECT s.* FROM sensors s
      INNER JOIN nodes n ON s.node_id = n.id
      WHERE s.id = ? AND s.node_id = ?
        AND s.deleted_at IS NULL
        AND n.deleted_at IS NULL
      LIMIT 1
      """

      case Repo.query(query, [sensor_id_int, node_id_int]) do
        {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
          sensor = cols |> Enum.zip(row) |> Map.new()
          {:ok, sensor}

        {:ok, _} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      ArgumentError -> {:error, :not_found}
      e ->
        Logger.error("Exception validating sensor: #{inspect(e)}")
        {:error, :not_found}
    end
  end
end
