defmodule Ecosense.ReadingQueue do
  @moduledoc """
  Cola para encolar lecturas de dispositivos IoT y guardarlas en BD de forma asíncrona.
  - Respuesta rápida al dispositivo (202 Accepted)
  - Procesamiento en lotes para reducir carga en la BD
  - Flush periódico y por tamaño de lote
  """
  use GenServer

  require Logger

  alias Ecosense.Repo

  @default_batch_size 10
  @default_flush_interval_ms 3_000

  # API pública
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Encola una lectura. Devuelve :ok de inmediato.
  La lectura debe tener: sensor_id, source, timestamp, value, node_id (para last_seen)
  """
  def enqueue(reading) when is_map(reading) do
    GenServer.cast(__MODULE__, {:enqueue, reading})
    :ok
  end

  @doc "Devuelve la cantidad de lecturas pendientes en la cola."
  def pending_count do
    GenServer.call(__MODULE__, :pending_count)
  end

  # Callbacks GenServer
  @impl true
  def init(opts) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    flush_interval = Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms)

    # Timer para flush periódico
    ref = Process.send_after(self(), :flush, flush_interval)

    state = %{
      queue: :queue.new(),
      batch_size: batch_size,
      flush_interval_ms: flush_interval,
      flush_timer_ref: ref
    }

    Logger.info(
      "ReadingQueue started (batch_size=#{batch_size}, flush_interval=#{flush_interval}ms)"
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue, reading}, state) do
    queue = :queue.in(reading, state.queue)
    new_state = %{state | queue: queue}
    len = :queue.len(queue)
    sensor_id = reading["sensor_id"] || reading[:sensor_id]
    value = reading["value"] || reading[:value]

    Logger.info(
      "ReadingQueue: +1 encolado [sensor_id=#{sensor_id}, value=#{value}] | cola: #{len}"
    )

    # Flush si alcanzamos el tamaño del lote
    if len >= state.batch_size do
      new_state = cancel_timer(new_state)
      Process.send(self(), :flush, [])
      {:noreply, new_state}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:pending_count, _from, state) do
    count = :queue.len(state.queue)
    {:reply, count, state}
  end

  @impl true
  def handle_info(:flush, state) do
    {items, remaining} = dequeue_batch(state.queue, state.batch_size)
    remaining_count = :queue.len(remaining)

    if length(items) > 0 do
      Logger.info(
        "ReadingQueue: subiendo #{length(items)} registros a BD | cola restante: #{remaining_count}"
      )

      Task.start(fn -> flush_to_db(items, remaining_count) end)
    end

    # Reprogramar timer
    ref = Process.send_after(self(), :flush, state.flush_interval_ms)
    new_state = %{state | queue: remaining, flush_timer_ref: ref}
    {:noreply, new_state}
  end

  defp dequeue_batch(queue, max) do
    Enum.reduce_while(1..max, {[], queue}, fn _, {acc, q} ->
      case :queue.out(q) do
        {{:value, item}, new_q} -> {:cont, {[item | acc], new_q}}
        {:empty, _} -> {:halt, {Enum.reverse(acc), q}}
      end
    end)
  end

  defp flush_to_db(items, remaining_count) do
    try do
      Repo.transaction(fn ->
        node_ids = Enum.map(items, & &1["node_id"]) |> Enum.uniq() |> Enum.reject(&is_nil/1)

        Enum.each(items, fn reading ->
          sensor_id = reading["sensor_id"] || reading[:sensor_id]
          source = reading["source"] || reading[:source] || "device"
          value = reading["value"] || reading[:value]
          # MySQL espera 'YYYY-MM-DD HH:MM:SS'; convertir ISO8601 si viene como string
          timestamp = format_timestamp_for_mysql(reading["timestamp"] || reading[:timestamp])

          {query, params} =
            if timestamp do
              {"INSERT INTO readings (sensor_id, source, timestamp, value) VALUES (?, ?, ?, ?)",
               [sensor_id, source, timestamp, value]}
            else
              {"INSERT INTO readings (sensor_id, source, value) VALUES (?, ?, ?)",
               [sensor_id, source, value]}
            end

          case Repo.query(query, params) do
            {:ok, _} -> :ok
            {:error, reason} -> raise "INSERT reading failed: #{inspect(reason)}"
          end
        end)

        Enum.each(node_ids, fn node_id ->
          node_id_int = if is_binary(node_id), do: String.to_integer(node_id), else: node_id

          case Repo.query("UPDATE nodes SET last_seen_at = CURRENT_TIMESTAMP WHERE id = ?", [
                 node_id_int
               ]) do
            {:ok, _} -> :ok
            {:error, reason} -> raise "UPDATE last_seen failed: #{inspect(reason)}"
          end
        end)
      end)

      Logger.info(
        "ReadingQueue: ✓ #{length(items)} lecturas guardadas en BD | cola restante: #{remaining_count}"
      )
    rescue
      e ->
        Logger.error(
          "ReadingQueue flush error: #{inspect(e)}, stacktrace: #{inspect(__STACKTRACE__)}"
        )
    end
  end

  # MySQL DATETIME espera 'YYYY-MM-DD HH:MM:SS'. ISO8601 tiene 'T' y puede tener microsegundos.
  defp format_timestamp_for_mysql(nil), do: nil

  defp format_timestamp_for_mysql(%NaiveDateTime{} = dt) do
    NaiveDateTime.to_string(dt) |> String.replace("T", " ") |> String.slice(0..18)
  end

  defp format_timestamp_for_mysql(str) when is_binary(str) do
    str
    |> String.replace("T", " ")
    |> String.replace("Z", "")
    |> String.slice(0..18)
  end

  defp format_timestamp_for_mysql(_), do: nil

  defp cancel_timer(state) do
    if state.flush_timer_ref do
      Process.cancel_timer(state.flush_timer_ref)
    end

    %{state | flush_timer_ref: nil}
  end
end
