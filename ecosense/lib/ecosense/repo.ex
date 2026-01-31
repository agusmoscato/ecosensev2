defmodule Ecosense.Repo do
  use Ecto.Repo,
    otp_app: :ecosense,
    adapter: Ecto.Adapters.MyXQL
end
