defmodule EcosenseWeb.DeviceAuthPlug do
  @moduledoc """
  Plug para autenticación de dispositivos IoT mediante API Key.
  Lee el header x-api-key y busca el nodo correspondiente.
  """
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  alias Ecosense.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    api_key = get_req_header(conn, "x-api-key") |> List.first() |> maybe_trim()

    if api_key_valid?(api_key) do
      case find_node_by_api_key(api_key) do
        {:ok, node} ->
          assign(conn, :current_node, node)

        {:error, :not_found} ->
          Logger.warning("DeviceAuthPlug: API key no encontrada en BD")

          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Validación incorrecta: API key inválida o nodo no encontrado"})
          |> halt()

        {:error, reason} ->
          Logger.error("DeviceAuthPlug error: #{inspect(reason)}")

          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Validación incorrecta: Error al verificar la API key"})
          |> halt()
      end
    else
      Logger.warning("DeviceAuthPlug: Header x-api-key faltante o vacío")

      conn
      |> put_status(:unauthorized)
      |> json(%{
        error: "Validación incorrecta: Se requiere el header x-api-key con una API key válida"
      })
      |> halt()
    end
  end

  defp maybe_trim(nil), do: nil
  defp maybe_trim(s) when is_binary(s), do: String.trim(s)
  defp maybe_trim(_), do: nil

  defp api_key_valid?(nil), do: false
  defp api_key_valid?(""), do: false
  defp api_key_valid?(s) when is_binary(s) and byte_size(s) > 0, do: true
  defp api_key_valid?(_), do: false

  defp find_node_by_api_key(api_key) do
    try do
      query = """
      SELECT * FROM nodes
      WHERE api_key = ? AND deleted_at IS NULL
      LIMIT 1
      """

      case Repo.query(query, [api_key]) do
        {:ok, %MyXQL.Result{columns: cols, rows: [row]}} ->
          node = cols |> Enum.zip(row) |> Map.new() |> normalize_dates()
          {:ok, node}

        {:ok, _} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception in find_node_by_api_key: #{inspect(e)}")
        {:error, e}
    end
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
