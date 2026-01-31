import Config

# Enable Phoenix server if PHX_SERVER is set
if System.get_env("PHX_SERVER") do
  config :ecosense, EcosenseWeb.Endpoint, server: true
end

# HTTP config (dev + prod)
config :ecosense, EcosenseWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || "4000")]

# =========================
# DATABASE CONFIG (DEV / DOCKER)
# =========================
if config_env() != :prod do
  config :ecosense, Ecosense.Repo,
    adapter: Ecto.Adapters.MyXQL,
    username: System.get_env("DB_USER") || "ecosense",
    password: System.get_env("DB_PASSWORD") || "ecosense",
    database: System.get_env("DB_NAME") || "ecosense_dev",
    hostname: System.get_env("DB_HOST") || "db",
    port: 3306,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end

# =========================
# DATABASE CONFIG (PROD)
# =========================
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 =
    if System.get_env("ECTO_IPV6") in ~w(true 1),
      do: [:inet6],
      else: []

  config :ecosense, Ecosense.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

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
