defmodule EcosenseWeb.DashboardController do
  use EcosenseWeb, :controller

  # GET /dashboard — página con gráficos (selector de nodo)
  def index(conn, _params) do
    render(conn, :index, node_id: nil)
  end

  # GET /dashboard/history — página de histórico independiente
  def history(conn, _params) do
    render(conn, :history)
  end

  # GET /dashboard/:node_id — misma página con nodo preseleccionado
  def show(conn, %{"node_id" => _node_id} = params) do
    render(conn, :index, node_id: params["node_id"])
  end
end
