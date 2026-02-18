defmodule EcosenseWeb.Router do
  use EcosenseWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EcosenseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :device do
    plug :accepts, ["json"]
    plug EcosenseWeb.DeviceAuthPlug
  end

  pipeline :require_auth do
    plug EcosenseWeb.AuthPlug
  end

  # Login (sin autenticación)
  scope "/", EcosenseWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Rutas protegidas (requieren login)
  scope "/", EcosenseWeb do
    pipe_through [:browser, :require_auth]

    get "/", PageController, :home
    get "/dashboard", DashboardController, :index
    get "/dashboard/history", DashboardController, :history
    get "/dashboard/:node_id", DashboardController, :show

    get "/manage", ManagementController, :index
    get "/manage/nodes", ManagementController, :nodes
    get "/manage/sensors", ManagementController, :sensors
  end

  scope "/api", EcosenseWeb do
    pipe_through :api

    get "/dashboard", DashboardApiController, :show
    get "/dashboard/history", DashboardHistoryApiController, :show
    get "/stats", StatsController, :index

    # Lecturas: solo GET, show, update, delete. Para CREAR desde dispositivos usar POST /api/devices/readings (requiere x-api-key)
    resources "/readings", ReadingController, only: [:index, :show, :update, :delete]
    resources "/sensors", SensorController, only: [:index, :create, :update, :delete]
    resources "/nodes", NodeController, only: [:index, :create, :update, :delete]
  end

  scope "/api/devices", EcosenseWeb do
    pipe_through :device

    post "/readings", DeviceReadingController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", EcosenseWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ecosense, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EcosenseWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
