defmodule EcosenseWeb.ReadingController do
  use EcosenseWeb, :controller

  require Logger

  alias Ecosense.Sensors
  alias Ecosense.Sensors.Reading
  alias Ecosense.{InMemoryStore, Repo}

  action_fallback EcosenseWeb.FallbackController

  # GET /api/readings — igual que EcoSense: BD (raw) o fallback en memoria
  # Ruta: scope /api -> resources /readings (router.ex)
  def index(conn, _params) do
    readings =
      if repo_available?() do
        case fetch_from_db() do
          {:ok, rows} ->
            Logger.info("GET /api/readings: #{length(rows)} registros desde la base de datos")
            rows

          {:error, reason} ->
            Logger.warning("GET /api/readings: fallback a memoria. Error BD: #{inspect(reason)}")
            InMemoryStore.all()
        end
      else
        Logger.warning("GET /api/readings: Repo no disponible, usando memoria (vacía)")
        InMemoryStore.all()
      end

    json(conn, readings)
  end

  # Para CREAR lecturas desde dispositivos IoT usar POST /api/devices/readings (requiere x-api-key)

  def show(conn, %{"id" => id}) do
    reading = Sensors.get_reading!(id)
    render(conn, :show, reading: reading)
  end

  def update(conn, %{"id" => id, "reading" => reading_params}) do
    reading = Sensors.get_reading!(id)

    with {:ok, %Reading{} = reading} <- Sensors.update_reading(reading, reading_params) do
      render(conn, :show, reading: reading)
    end
  end

  # Soft delete: pone fecha en deleted_at (no borra el registro)
  def delete(conn, %{"id" => id}) do
    if repo_available?() do
      case soft_delete_in_db(id) do
        :ok ->
          conn
          |> put_status(:ok)
          |> json(%{message: "El registro se eliminó correctamente."})

        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "reading not found or already deleted"})
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "database not available"})
    end
  end

  defp repo_available? do
    case Process.whereis(Ecosense.Repo) do
      nil -> false
      _pid -> true
    end
  end

  defp fetch_from_db do
    try do
      # Excluir registros con soft delete (deleted_at IS NULL)
      query = "SELECT * FROM readings WHERE deleted_at IS NULL ORDER BY id DESC LIMIT 100"

      case Repo.query(query) do
        {:ok, %MyXQL.Result{columns: cols, rows: rows}} ->
          mapped =
            Enum.map(rows, fn row ->
              cols
              |> Enum.zip(row)
              |> Map.new()
            end)

          {:ok, mapped}

        {:error, reason} ->
          Logger.error("Database error: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception fetching from DB: #{inspect(e)}")
        {:error, e}
    end
  end

  # Soft delete: UPDATE deleted_at = NOW() WHERE id = ? AND deleted_at IS NULL
  defp soft_delete_in_db(id_str) do
    try do
      id = String.to_integer(id_str)

      query =
        "UPDATE readings SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND deleted_at IS NULL"

      case Repo.query(query, [id]) do
        {:ok, %MyXQL.Result{num_rows: 1}} ->
          Logger.info("Reading id=#{id} soft deleted")
          :ok

        {:ok, _} ->
          :not_found

        {:error, reason} ->
          Logger.error("Soft delete failed: #{inspect(reason)}")
          :not_found
      end
    rescue
      ArgumentError ->
        :not_found

      e ->
        Logger.error("Exception in soft delete: #{inspect(e)}")
        :not_found
    end
  end
end
