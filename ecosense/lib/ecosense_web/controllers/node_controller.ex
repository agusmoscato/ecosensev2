defmodule EcosenseWeb.NodeController do
  use EcosenseWeb, :controller

  require Logger
  alias Ecosense.Repo

  @valid_statuses ~w(activo inactivo mantenimiento)

  # ================================
  # GET /api/nodes
  # ================================
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

  # ================================
  # POST /api/nodes
  # ================================
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

  # ================================
  # PUT /api/nodes/:id  (FALTABA)
  # ================================
  def update(conn, %{"id" => id} = params) do
    if repo_available?() do
      case update_node_in_db(id, params) do
        {:ok, updated} ->
          json(conn, updated)

        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Nodo no encontrado."})

        {:error, reason} ->
          Logger.error("Update node failed: #{inspect(reason)}")
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No se pudo actualizar el nodo."})
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Base de datos no disponible."})
    end
  end

  # ================================
  # DELETE /api/nodes/:id
  # ================================
  def delete(conn, %{"id" => id}) do
    if repo_available?() do
      case soft_delete_node_in_db(id) do
        :ok ->
          json(conn, %{message: "El nodo se eliminó correctamente."})

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

  # ================================
  # DB HELPERS
  # ================================

  defp fetch_nodes_from_db do
    try do
      query = "SELECT n.*, sensor_count FROM nodes n LEFT JOIN ( SELECT COUNT(id) as sensor_count, node_id FROM sensors GROUP BY node_id ) s ON n.id = s.node_id WHERE n.deleted_at IS NULL ORDER BY n.id"

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
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception fetching nodes: #{inspect(e)}")
        {:error, e}
    end
  end

  defp create_node_in_db(params) do
    name = params["name"]
    status = params["status"]

    cond do
      name in [nil, ""] -> {:error, :invalid_name}
      status not in @valid_statuses -> {:error, :invalid_status}
      true ->
        try do
          api_key = generate_api_key()

          address = params["address"] || ""
          city = params["city"] || ""
          latitude = normalize_float(params["latitude"])
          longitude = normalize_float(params["longitude"])
          notes = params["notes"] || ""

          query = """
          INSERT INTO nodes (name, address, city, latitude, longitude, status, notes, api_key)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """

          case Repo.query(query, [
            name, address, city, latitude, longitude, status, notes, api_key
          ]) do
            {:ok, %{last_insert_id: new_id}} ->
              fetch_node_by_id(new_id)

            {:error, reason} ->
              {:error, reason}
          end
        rescue e ->
          {:error, e}
        end
    end
  end

  defp update_node_in_db(id_str, params) do
    id = String.to_integer(id_str)
    fields =
      Enum.filter([
        {"name", params["name"]},
        {"address", params["address"]},
        {"city", params["city"]},
        {"latitude", normalize_float(params["latitude"])},
        {"longitude", normalize_float(params["longitude"])},
        {"status", params["status"]},
        {"notes", params["notes"]}
      ], fn {_k, v} -> v != nil end)

    if fields == [] do
      {:error, :empty}
    else
      set_clause =
        fields
        |> Enum.map(fn {k, _} -> "#{k} = ?" end)
        |> Enum.join(", ")

      values = Enum.map(fields, fn {_, v} -> v end)

      query = """
      UPDATE nodes
      SET #{set_clause}, updated_at = NOW()
      WHERE id = ? AND deleted_at IS NULL
      """

      case Repo.query(query, values ++ [id]) do
        {:ok, %{num_rows: 0}} -> :not_found
        {:ok, _} -> fetch_node_by_id(id)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_node_by_id(id) do
    case Repo.query("SELECT * FROM nodes WHERE id = ?", [id]) do
      {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
        {:ok, cols |> Enum.zip(row) |> Map.new() |> normalize_row_for_json()}

      _ ->
        :not_found
    end
  end

  defp soft_delete_node_in_db(id_str) do
    try do
      id = String.to_integer(id_str)
      query = "UPDATE nodes SET deleted_at = NOW() WHERE id = ? AND deleted_at IS NULL"

      case Repo.query(query, [id]) do
        {:ok, %MyXQL.Result{num_rows: 1}} -> :ok
        _ -> :not_found
      end
    rescue
      _ -> :not_found
    end
  end

  # ================================
  # UTILS
  # ================================
  defp normalize_float(nil), do: nil
  defp normalize_float(""), do: nil
  defp normalize_float(v) when is_binary(v), do: String.to_float(v)
  defp normalize_float(v), do: v

  defp generate_api_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp normalize_row_for_json(row) do
    row
    |> Enum.map(fn
      {k, %NaiveDateTime{} = dt} -> {to_string(k), NaiveDateTime.to_iso8601(dt) <> "Z"}
      {k, %DateTime{} = dt} -> {to_string(k), DateTime.to_iso8601(dt)}
      {k, v} -> {to_string(k), v}
    end)
    |> Map.new()
  end

  defp repo_available?, do: Process.whereis(Ecosense.Repo) != nil
end
