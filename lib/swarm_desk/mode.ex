defmodule SwarmDesk.Mode do
  def clairic?, do: :persistent_term.get({__MODULE__, :clairic}, false)
  def set_clairic(on) when is_boolean(on), do: :persistent_term.put({__MODULE__, :clairic}, on)
end
