defmodule TokenManagerWeb.Router do
  use TokenManagerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TokenManagerWeb do
    pipe_through :api

    post "/tokens/activate", TokenController, :activate
    get "/tokens", TokenController, :index
    get "/tokens/:id", TokenController, :show
    get "/tokens/:id/history", TokenController, :history
    post "/tokens/clear", TokenController, :clear_active
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:token_manager, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
