defmodule Tesla.Middleware.TelemetryTest do
  use ExUnit.Case, async: true

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Telemetry

    adapter fn env ->
      case env.url do
        "/telemetry" -> {:ok, env}
        "/telemetry_error" -> {:error, :econnrefused}
        "/telemetry_exception" -> raise "some exception"
      end
    end
  end

  setup do
    Application.ensure_all_started(:telemetry)

    on_exit(fn ->
      :telemetry.list_handlers([])
      |> Enum.each(&:telemetry.detach(&1.id))
    end)

    :ok
  end

  test "events are all emitted properly" do
    Enum.each(["/telemetry", "/telemetry_error"], fn path ->
      :telemetry.attach("start event", [:tesla, :request, :start], &echo_event/4, %{
        caller: self()
      })

      :telemetry.attach("stop event", [:tesla, :request, :stop], &echo_event/4, %{
        caller: self()
      })

      :telemetry.attach("legacy event", [:tesla, :request], &echo_event/4, %{
        caller: self()
      })

      Client.get(path)

      assert_receive {:event, [:tesla, :request, :start], %{system_time: _time},
                      %{env: %Tesla.Env{url: ^path, method: :get}}}

      assert_receive {:event, [:tesla, :request, :stop], %{duration: _time},
                      %{env: %Tesla.Env{url: ^path, method: :get}}}

      assert_receive {:event, [:tesla, :request], %{request_time: _time}, %{result: _result}}
    end)
  end

  test "with an exception raised" do
    :telemetry.attach("with_exception", [:tesla, :request, :exception], &echo_event/4, %{
      caller: self()
    })

    assert_raise RuntimeError, fn ->
      Client.get("/telemetry_exception")
    end

    assert_receive {:event, [:tesla, :request, :exception], %{duration: _time},
                    %{
                      kind: _kind,
                      reason: _reason,
                      stacktrace: _stacktrace
                    }}
  end

  def echo_event(event, measurements, metadata, config) do
    send(config.caller, {:event, event, measurements, metadata})
  end
end
