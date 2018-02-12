defmodule ElephantTest do
  use ExUnit.Case
  doctest Elephant

  test "greets the world" do
    assert Elephant.hello() == :world
  end
end
