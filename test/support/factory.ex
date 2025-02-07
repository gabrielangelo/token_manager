defmodule TokenManager.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: TokenManager.Repo

  use TokenManager.TokenFactory
end
