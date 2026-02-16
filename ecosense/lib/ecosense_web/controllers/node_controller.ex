defmodule EcosenseWeb.NodeController do
  use EcosenseWeb, :controller

  require Logger

  alias Ecosense.Repo

  @valid_statuses ~w(activo inactivo mantenimiento)

  # GET /api/nodes — lista todos los nodos (excluye soft-deleted)
  def index(conn, _params) do
    nodes =
      if repo_available?() do
        case fetch_nodes_from_db() do
          {:ok, rows} ->
            Logger.info("GET /api/nodes: #{length(rows)} nodos desde la base de datos")
            rows

          {:error, reason} ->
            Logger.warning("GET /api/nodes: Error BD: #{inspect(reason)}")
            []
        end
      else
        Logger.warning("GET /api/nodes: Repo no disponible")
        []
      end

    json(conn, nodes)
  end

  # POST /api/nodes — crea un nodo (name y status requeridos; otros campos opcionales)
  # status: activo | inactivo | mantenimiento
  def create(conn, params) do
    if repo_available?() do
      case create_node_in_db(params) do
        {:ok, node} ->
          conn
          |> put_status(:created)
          |> json(node)

        {:error, :invalid_name} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "El campo name es requerido."})

        {:error, :invalid_status} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "El campo status es requerido y debe ser: activo, inactivo o mantenimiento."})

        {:error, reason} ->
          Logger.error("Create node failed: #{inspect(reason)}")
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No se pudo crear el nodo."})
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Base de datos no disponible."})
    end
  end

  # DELETE /api/nodes/:id — soft delete (pone fecha en deleted_at)
  def delete(conn, %{"id" => id}) do
    if repo_available?() do
      case soft_delete_node_in_db(id) do
        :ok ->
          conn
          |> put_status(:ok)
          |> json(%{message: "El nodo se eliminó correctamente."})

        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Nodo no encontrado o ya fue eliminado."})
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

  defp fetch_nodes_from_db do
    try do
      query = "SELECT * FROM nodes WHERE deleted_at IS NULL ORDER BY id"

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
          Logger.error("Database error (nodes): #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception fetching nodes from DB: #{inspect(e)}")
        {:error, e}
    end
  end

  defp create_node_in_db(params) do
    name = params["name"] || params[:name]
    status = params["status"] || params[:status]

    cond do
      name == nil or name == "" ->
        {:error, :invalid_name}

      status == nil or status == "" ->
        {:error, :invalid_status}

      not (to_string(status) in @valid_statuses) ->
        {:error, :invalid_status}

      true ->
        try do
          # Generar API key segura (32 caracteres hexadecimales)
          api_key = generate_api_key()
          
          # Campos opcionales con valores por defecto
          address = params["address"] || params[:address] || ""
          city = params["city"] || params[:city] || ""
          latitude = params["latitude"] || params[:latitude] || nil
          longitude = params["longitude"] || params[:longitude] || nil
          notes = params["notes"] || params[:notes] || ""
          status_str = to_string(status)

          query = """
          INSERT INTO nodes (name, address, city, latitude, longitude, status, notes, api_key)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """

          case Repo.query(query, [
            to_string(name),
            to_string(address),
            to_string(city),
            latitude,
            longitude,
            status_str,
            to_string(notes),
            api_key
          ]) do
            {:ok, _result} ->
              case Repo.query("SELECT * FROM nodes WHERE id = LAST_INSERT_ID()") do
                {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
                  row_map = cols |> Enum.zip(row) |> Map.new() |> normalize_row_for_json()
                  Logger.info("Node created, id=#{row_map["id"]}, api_key=#{api_key}")
                  {:ok, row_map}

                _ ->
                  {:ok, %{"name" => name, "status" => status_str, "api_key" => api_key}}
              end

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          e ->
            Logger.error("Exception creating node: #{inspect(e)}")
            {:error, e}
        end
    end
  end

  defp generate_api_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp soft_delete_node_in_db(id_str) do
    try do
      id = String.to_integer(id_str)
      query = "UPDATE nodes SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND deleted_at IS NULL"

      case Repo.query(query, [id]) do
        {:ok, %MyXQL.Result{num_rows: 1}} ->
          Logger.info("Node id=#{id} soft deleted")
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
