defmodule TswIoWeb.PageController do
  use TswIoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
