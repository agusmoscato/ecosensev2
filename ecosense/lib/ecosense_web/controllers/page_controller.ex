defmodule EcosenseWeb.PageController do
  use EcosenseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
