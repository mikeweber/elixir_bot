defmodule Entity do
  def to_atom(%Planet{} = entity),      do: Planet.to_atom(entity)
  def to_atom(%Ship{} = entity),        do: Ship.to_atom(entity)
  def to_atom(%Position{ x: x, y: y }), do: String.to_atom("#{x}x#{y}")
end
