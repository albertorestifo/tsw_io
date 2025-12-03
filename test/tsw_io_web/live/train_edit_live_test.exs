defmodule TswIoWeb.TrainEditLiveTest do
  use TswIoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TswIo.Train, as: TrainContext

  describe "new train form" do
    test "pre-fills identifier from query params when configuring detected train", %{conn: conn} do
      # When a train is detected but not configured, the user clicks "Configure"
      # which navigates to /trains/new?identifier=BR_Class_66
      # The identifier should be pre-filled in the form
      {:ok, _view, html} = live(conn, ~p"/trains/new?identifier=BR_Class_66")

      # Verify the identifier field is pre-filled with the detected train identifier
      assert html =~ ~s(value="BR_Class_66")
    end

    test "renders empty identifier when no connect params provided", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/trains/new")

      # The identifier field should be empty when no identifier is passed
      assert html =~ "Train Identifier"
      assert html =~ ~s(placeholder="e.g., BR_Class_66")
      # Verify the identifier input has an empty value
      assert html =~ ~s(name="train[identifier]")
      assert html =~ ~s(id="train_identifier" value="")
    end

    test "saves train with pre-filled identifier from query params", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/trains/new?identifier=BR_Class_66")

      # Fill in the name and submit the form
      view
      |> form("form[phx-submit='save_train']",
        train: %{name: "Class 66", description: "British freight locomotive"}
      )
      |> render_submit()

      # Verify the train was created with the pre-filled identifier
      [train] = TrainContext.list_trains()
      assert train.identifier == "BR_Class_66"
      assert train.name == "Class 66"
      assert train.description == "British freight locomotive"
    end
  end
end
