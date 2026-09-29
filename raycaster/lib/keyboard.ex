defmodule Raycaster.Keyboard do
  @moduledoc """
  The key matrix as a process: idle it blocks, and an interrupt wakes it.

  The owner, the process that called `start_link/0`, gets `{:key, :down, label}`
  and `{:key, :up, label}`, with labels from `Raycaster.Keymap`. Positions without
  a label are ignored.
  """

  use GenServer

  @rows [38, 39, 40, 41, 42, 45]
  @cols [37, 36, 35, 48, 34, 33, 47, 46, 21, 18, 17, 16, 15]

  # AtomVM's Enum has no with_index/1, so the numbering is done here, while
  # compiling on the laptop.
  @indexed_rows Enum.with_index(@rows)
  @indexed_cols Enum.with_index(@cols)

  @interval 20

  def start_link do
    GenServer.start_link(__MODULE__, self())
  end

  @impl true
  def init(owner) do
    # The port driver is only needed for interrupts; reads and writes go
    # straight to the NIFs.
    gpio = GPIO.open()
    setup()

    {:ok, idle(%{owner: owner, gpio: gpio, pressed: []})}
  end

  # Nothing was held, so this is a real key going down: stop listening and
  # start looking.
  @impl true
  def handle_info({:gpio_interrupt, _pin}, %{pressed: []} = state) do
    # Scanning drives rows one at a time, which would retrigger the interrupts.
    disarm(state.gpio)

    {:noreply, scan_and_report(state)}
  end

  # Something is already held, so this is an echo of our own scanning.
  def handle_info({:gpio_interrupt, _pin}, state) do
    {:noreply, state}
  end

  def handle_info(:scan, state) do
    {:noreply, scan_and_report(state)}
  end

  # Nothing calls or casts to this server, but the defaults that `use
  # GenServer` would supply are built on :erlang.phash2/2, which AtomVM does
  # not have.
  @impl true
  def handle_call(_message, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_cast(_message, state), do: {:noreply, state}

  # Rows all low, so closing any key pulls its own column down and fires an
  # interrupt. The process now costs nothing until one arrives.
  defp idle(state) do
    all_rows(:low)
    flush()
    arm(state.gpio)

    # A key pressed between the last scan and arming raised no edge, so look
    # once. Reading columns drives no rows and cannot raise an edge itself.
    if any_column_low?(), do: send(self(), {:gpio_interrupt, :recheck})

    %{state | pressed: []}
  end

  # Only the difference between two scans is news: the rest is a key being
  # held down.
  defp scan_and_report(state) do
    pressed = scan()

    Enum.each(pressed -- state.pressed, fn key -> report(state.owner, :down, key) end)
    Enum.each(state.pressed -- pressed, fn key -> report(state.owner, :up, key) end)

    case pressed do
      [] ->
        idle(state)

      _held ->
        Process.send_after(self(), :scan, @interval)
        %{state | pressed: pressed}
    end
  end

  defp setup do
    # Columns idle high. A closed switch is the only thing that pulls one down.
    Enum.each(@cols, fn pin ->
      GPIO.set_pin_mode(pin, :input)
      GPIO.set_pin_pull(pin, :up)
    end)

    # Open drain, so writing :high releases a row instead of driving it and two
    # rows can never fight through a closed switch. ROW5 (GPIO45) boots pulled
    # down, so its pull-up has to be set explicitly.
    Enum.each(@rows, fn pin ->
      GPIO.set_pin_mode(pin, :output_od)
      GPIO.set_pin_pull(pin, :up)
      GPIO.digital_write(pin, :high)
    end)
  end

  defp arm(gpio), do: Enum.each(@cols, fn pin -> GPIO.set_int(gpio, pin, :falling) end)

  defp disarm(gpio), do: Enum.each(@cols, fn pin -> GPIO.remove_int(gpio, pin) end)

  # Interrupts raised by our own row driving are not news either.
  defp flush do
    receive do
      {:gpio_interrupt, _pin} -> flush()
    after
      0 -> :ok
    end
  end

  defp any_column_low?, do: Enum.any?(@cols, fn pin -> GPIO.digital_read(pin) == :low end)

  defp all_rows(level), do: Enum.each(@rows, fn pin -> GPIO.digital_write(pin, level) end)

  # With every row low, a column reads low if any key in it is closed, so one
  # sweep of the columns says which of them can hold a key at all. Only those
  # are read again while the rows are driven low one at a time: a key held or
  # two costs about half the GPIO calls of reading the whole matrix, and each
  # call is a NIF that takes on the order of 180 us on this chip.
  defp scan do
    case low_columns(@indexed_cols, []) do
      [] ->
        []

      active ->
        all_rows(:high)
        keys = scan_rows(@indexed_rows, active, [])
        all_rows(:low)
        keys
    end
  end

  defp low_columns([], acc), do: acc

  defp low_columns([{pin, _col} = column | rest], acc) do
    if GPIO.digital_read(pin) == :low do
      low_columns(rest, [column | acc])
    else
      low_columns(rest, acc)
    end
  end

  # Drive one row low at a time and see which of the active columns follow it.
  defp scan_rows([], _active, keys), do: keys

  defp scan_rows([{pin, row} | rows], active, keys) do
    GPIO.digital_write(pin, :low)
    keys = closed_columns(active, row, keys)
    GPIO.digital_write(pin, :high)

    scan_rows(rows, active, keys)
  end

  defp closed_columns([], _row, keys), do: keys

  defp closed_columns([{pin, col} | rest], row, keys) do
    if GPIO.digital_read(pin) == :low do
      closed_columns(rest, row, [{row, col} | keys])
    else
      closed_columns(rest, row, keys)
    end
  end

  defp report(owner, event, key) do
    case Raycaster.Keymap.label(key) do
      nil -> :ok
      label -> send(owner, {:key, event, label})
    end
  end
end
