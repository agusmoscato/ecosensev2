import Config

# Cargar .env del proyecto (misma idea que el otro EcoSense: pegas DATABASE_URL y listo)
# .env debe estar en la carpeta donde está mix.exs (ecosense/). Ejecuta mix phx.server desde ecosense/
# El archivo .env está en .gitignore; no subas contraseñas.
env_file = Path.join(File.cwd!(), ".env")

env_map =
  if File.exists?(env_file) do
    env_file
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      if line == "" or String.starts_with?(line, "#") do
        acc
      else
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            Map.put(
              acc,
              String.trim(key),
              String.trim(value) |> String.trim_leading("\"") |> String.trim_trailing("\"")
            )

          _ ->
            acc
        end
      end
    end)
  else
    %{}
  end

# Helper: leer variable de entorno o del .env cargado
get_env = fn key, default -> System.get_env(key) || Map.get(env_map, key) || default end

# Enable Phoenix server if PHX_SERVER is set
if System.get_env("PHX_SERVER") do
  config :ecosense, EcosenseWeb.Endpoint, server: true
end

# HTTP config (dev + prod)
config :ecosense, EcosenseWeb.Endpoint, http: [port: String.to_integer(get_env.("PORT", "4000"))]

# =========================
# BASE DE DATOS: solo Hostinger (DATABASE_URL en .env o variable de entorno)
# Sin DATABASE_URL la app no arranca.
# Formato: ecto://USER:PASSWORD@HOST:PUERTO/NOMBRE_BD  (mysql:// también vale)
# =========================
raw_db_url = get_env.("DATABASE_URL", "")

db_url =
  if raw_db_url != "" do
    String.replace(raw_db_url, "mysql://", "ecto://")
  else
    nil
  end

if !db_url do
  raise """
  DATABASE_URL es obligatoria. Configura la base de datos de Hostinger.

  1) Crea un archivo .env en la carpeta del proyecto (donde está mix.exs) con:
     DATABASE_URL=mysql://usuario:password@host/nombre_bd
     POOL_SIZE=5

  2) Arranca desde esa carpeta: mix phx.server

  O define la variable antes de arrancar:
     $env:DATABASE_URL="mysql://..."; mix phx.server
  """
end

pool_size = String.to_integer(get_env.("POOL_SIZE", "5"))

config :ecosense, Ecosense.Repo,
  url: db_url,
  pool_size: pool_size,
  timeout: 90_000,
  connect_timeout: 30_000,
  handshake_timeout: 30_000,
  queue_target: 10_000,
  queue_interval: 2_000,
  ssl: false

# =========================
# PROD: exige SECRET_KEY_BASE
# =========================
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :ecosense, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ecosense, EcosenseWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
