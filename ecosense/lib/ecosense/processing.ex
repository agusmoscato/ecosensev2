defmodule Ecosense.Processing do
  @moduledoc """
  Validaciones, transformaciones y detección de alertas para lecturas.
  Formato Hostinger: sensor_id (1-9), source, value (número o string), timestamp opcional.
  """

  @spec validate(map()) :: :ok | {:error, String.t()}
  # Con sensor_id: válido para tabla Hostinger (sensor_id 1-9, value número o string)
  def validate(%{"sensor_id" => sid, "value" => v}) when is_integer(sid) and sid in 1..99 do
    validate_value(v)
  end

  def validate(%{"sensor_id" => sid, "value" => v}) when is_binary(sid) do
    case Integer.parse(sid) do
      {n, _} when n in 1..99 -> validate_value(v)
      _ -> {:error, "sensor_id debe ser un número entre 1 y 99"}
    end
  end

  def validate(%{"value" => v}) when is_number(v) and v >= -100 and v <= 200, do: :ok
  def validate(%{"value" => _}), do: {:error, "valor fuera de rango"}
  def validate(%{"sensor_id" => _}), do: {:error, "falta el campo value"}

  def validate(_),
    do: {:error, "parametros inválidos: se requiere sensor_id y value (o al menos value)"}

  defp validate_value(v) when is_number(v) and v >= -100 and v <= 200, do: :ok
  defp validate_value(v) when is_binary(v), do: :ok
  defp validate_value(_), do: {:error, "value debe ser número o string"}

  @spec transform(map()) :: map()
  def transform(params) when is_map(params) do
    value_str =
      case params["value"] || params[:value] do
        v when is_number(v) -> to_string(v)
        v when is_binary(v) -> v
        v -> to_string(v)
      end

    params
    |> Map.put("value", value_str)
    |> Map.put_new("source", Map.get(params, "source") || Map.get(params, :source) || "esp32")
    |> Map.put_new("timestamp", NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601())
    |> maybe_put_sensor_id(params)
  end

  defp maybe_put_sensor_id(acc, params) do
    case params["sensor_id"] || params[:sensor_id] do
      nil -> acc
      sid when is_integer(sid) -> Map.put(acc, "sensor_id", sid)
      sid when is_binary(sid) -> Map.put(acc, "sensor_id", String.to_integer(sid))
      sid -> Map.put(acc, "sensor_id", sid)
    end
  end

  @spec check_alert(map(), %{min: number(), max: number()}) :: {:alert, atom()} | :ok
  def check_alert(%{"value" => v}, opts), do: check_alert_value(parse_value(v), opts)
  def check_alert(_, _), do: :ok

  defp parse_value(v) when is_number(v), do: v

  defp parse_value(v) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_value(_), do: nil

  defp check_alert_value(nil, _), do: :ok
  defp check_alert_value(v, %{min: min, max: _max}) when v < min, do: {:alert, :below_min}
  defp check_alert_value(v, %{min: _min, max: max}) when v > max, do: {:alert, :above_max}
  defp check_alert_value(_, _), do: :ok
end
