defmodule MyHack.App do
  @moduledoc """
  The hack itself, and the one module meant to be rewritten.

  Everything else is plumbing: `MyHack.Link` delivers what happens outside as
  messages, and `MyHack.Screen` shows what this module decides to show. What is
  here now only proves the round trip works:

    * anything published to `<base>/in/<name>` shows up on the screen
    * `<base>/in/ping` is answered on `<base>/out/pong`
    * `<base>/in/led` sets the LEDs: `off`, `#rrggbb` for all four, or four of
      them separated by spaces (see `MyHack.Leds`)
    * `<base>/in/face` sets the expression next to the title (see `MyHack.Face`)
    * typing on the badge fills an input line; Enter publishes it on
      `<base>/out/chat` and adds it to the log (Bksp deletes, Esc clears)

  Other local inputs (temperature, accelerometer) belong here too: start them
  from `init/1` and have them send this process messages.
  """

  use GenServer

  alias MyHack.{Cp437, Face, Keyboard, Leds, Link, Screen, Typing}

  @history 50
  @max_input 120

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    screen = Keyword.fetch!(opts, :screen)
    {:ok, link} = Link.start_link(Keyword.fetch!(opts, :link))
    {:ok, _keyboard} = Keyboard.start_link()

    # LEDs keep whatever they were last told, also across a restart of the app.
    leds = Leds.open()
    Leds.show(leds, "off")

    Screen.update(screen, %{title: Keyword.fetch!(opts, :title), lines: []})

    {:ok, %{screen: screen, link: link, leds: leds, lines: [], input: "", shift: 0}}
  end

  @impl true
  def handle_call(_message, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_cast(_message, state), do: {:noreply, state}

  @impl true
  def handle_info({:link, status}, state) do
    Screen.update(state.screen, %{link: status})

    {:noreply, state}
  end

  def handle_info({:key, :down, label}, state), do: {:noreply, press(state, label)}

  def handle_info({:key, :up, label}, state), do: {:noreply, release(state, label)}

  def handle_info({:message, "ping", _payload}, state) do
    Link.publish(state.link, "pong", "pong")

    {:noreply, remember(state, "ping")}
  end

  def handle_info({:message, "led", spec}, state) do
    if Leds.show(state.leds, spec) == :error, do: IO.puts("led: cannot read #{inspect(spec)}")

    {:noreply, state}
  end

  def handle_info({:message, "face", name}, state) do
    if Face.known?(name),
      do: Screen.update(state.screen, %{face: name}),
      else: IO.puts("face: no such face #{inspect(name)}")

    {:noreply, state}
  end

  def handle_info({:message, name, payload}, state) do
    {:noreply, remember(state, Cp437.from_utf8(name <> ": " <> payload))}
  end

  # Shift is a count, so holding both and letting go of one still counts as held.
  defp press(state, shift) when shift in ["LShift", "RShift"] do
    %{state | shift: state.shift + 1}
  end

  defp press(state, "Enter"), do: send_input(state)
  defp press(state, "Esc"), do: sync(%{state | input: ""})

  defp press(state, "Bksp") do
    size = byte_size(state.input)
    sync(%{state | input: binary_part(state.input, 0, max(size - 1, 0))})
  end

  defp press(state, label) do
    case Typing.char(label, state.shift > 0) do
      char when is_binary(char) and byte_size(state.input) < @max_input ->
        sync(%{state | input: state.input <> char})

      _ ->
        state
    end
  end

  defp release(state, shift) when shift in ["LShift", "RShift"] do
    %{state | shift: max(state.shift - 1, 0)}
  end

  defp release(state, _label), do: state

  defp send_input(%{input: ""} = state), do: state

  defp send_input(state) do
    Link.publish(state.link, "chat", state.input)

    sync(add_line(%{state | input: ""}, "me: " <> state.input))
  end

  # Oldest first, so the newest lands at the bottom.
  defp remember(state, line), do: sync(add_line(state, line))

  defp add_line(state, line), do: %{state | lines: last(state.lines ++ [line], @history)}

  defp sync(state) do
    Screen.update(state.screen, %{lines: state.lines, input: state.input})

    state
  end

  defp last(list, count), do: :lists.nthtail(max(length(list) - count, 0), list)
end
