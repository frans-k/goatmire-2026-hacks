defmodule MyHack.Scene do
  @moduledoc """
  What is on the screen, as a pure function of a small model.

  The scene knows nothing about Wi-Fi or MQTT; it is told what to show with
  `{:update, changes}` and redraws. Model keys:

    * `:wifi` is `:down`, `:connecting` or `{:up, ip}`
    * `:link` is `:down` or `:up`
    * `:title` is the heading in the body
    * `:face` is the name of a `MyHack.Face`, drawn beside the heading
    * `:lines` is the log, oldest first; long lines are wrapped
    * `:input` is the text being typed, shown on the bottom line
  """

  alias MyHack.Face

  @bar_height 20
  @line_height 20
  @margin 8
  # Where the log starts, and how much room the input line takes at the bottom.
  @body_top 64
  @input_height 32
  # Built-in font is 8 px wide.
  @char_width 8

  @background 0x000000
  @bar 0x202020
  @text 0xFFFFFF
  @dim 0x808080
  @face 0xFFD700
  @good 0x00C000
  @warn 0xE0A000
  @bad 0xC00000

  def start_link(args, opts) do
    :avm_scene.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    state = %{
      width: Keyword.fetch!(args, :width),
      height: Keyword.fetch!(args, :height),
      wifi: :down,
      link: :down,
      title: "",
      face: "neutral",
      lines: [],
      input: ""
    }

    {:ok, state}
  end

  # Returning [{:push, items}] is what sends the display list to the panel.
  def handle_info({:update, changes}, state) do
    state = Map.merge(state, changes)

    {:noreply, state, [{:push, render(state)}]}
  end

  # The first item is on top, the last is drawn first: the background rectangle
  # goes at the end.
  defp render(state) do
    max_chars = div(state.width - 2 * @margin, @char_width)
    # Below the log: a rule, then the input line.
    max_lines = div(state.height - @body_top - @input_height, @line_height)

    rows = wrap_all(state.lines, max_chars)
    body = body(last(rows, max_lines), 0, max_chars)

    [
      {:text, state.width - 4 * @char_width - 4, 2, :default16px, link_color(state.link),
       :transparent, "mqtt"},
      {:text, 4, 2, :default16px, wifi_color(state.wifi), :transparent, wifi_text(state.wifi)},
      {:text, @margin, @bar_height + 8, :default16px, @dim, :transparent,
       clip(state.title, max_chars - div(Face.size() + @margin, @char_width))},
      {:text, @margin, state.height - @input_height + 6, :default16px, @text, :transparent,
       input_line(state.input, max_chars)}
    ] ++
      Face.items(state.face, state.width - Face.size() - @margin, @bar_height + 2, @face) ++
      body ++
      [
        {:rect, 0, state.height - @input_height, state.width, 1, @dim},
        {:rect, 0, 0, state.width, @bar_height, @bar},
        {:rect, 0, 0, state.width, state.height, @background}
      ]
  end

  # When there are more lines than rows, the newest are the ones worth keeping.
  defp last(list, count), do: :lists.nthtail(max(length(list) - count, 0), list)

  # AtomVM's Enum has no with_index/1, so the row is counted by hand.
  defp body([], _row, _max_chars), do: []

  defp body([line | rest], row, max_chars) do
    [
      {:text, @margin, @body_top + row * @line_height, :default16px, @text, :transparent,
       clip(line, max_chars)}
      | body(rest, row + 1, max_chars)
    ]
  end

  defp wifi_text(:down), do: "wifi --"
  defp wifi_text(:connecting), do: "wifi connecting"
  defp wifi_text({:up, ip}), do: ip

  defp wifi_color(:down), do: @bad
  defp wifi_color(:connecting), do: @warn
  defp wifi_color({:up, _ip}), do: @good

  defp link_color(:up), do: @good
  defp link_color(:down), do: @bad

  # A long message becomes several rows instead of running off the panel.
  defp wrap_all(lines, max), do: Enum.flat_map(lines, fn line -> wrap(line, max) end)

  defp wrap(line, max) when byte_size(line) <= max, do: [line]

  defp wrap(line, max) do
    [binary_part(line, 0, max) | wrap(binary_part(line, max, byte_size(line) - max), max)]
  end

  # What has been typed, with a cursor; the end is what matters when it is too
  # long to fit.
  defp input_line(input, max_chars) do
    room = max_chars - 3
    shown = binary_part(input, max(byte_size(input) - room, 0), min(byte_size(input), room))

    "> " <> shown <> "_"
  end

  # Unclipped text runs off the panel. This counts bytes, which is right for
  # the CP437 font only while the text is ASCII.
  defp clip(text, max), do: binary_part(text, 0, min(byte_size(text), max))
end
