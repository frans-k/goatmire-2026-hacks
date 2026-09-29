defmodule MyHack.Badge do
  @moduledoc """
  Identity of this particular badge.
  """

  # Last three bytes of the factory MAC, so every badge gets its own topics
  # without anyone having to pick a number.
  def id do
    {:ok, <<_::binary-size(3), tail::binary-size(3)>>} = :esp.get_default_mac()

    Base.encode16(tail, case: :lower)
  end
end
