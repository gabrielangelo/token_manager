defmodule TokenManager.Factory do
  use ExMachina.Ecto, repo: TokenManager.Repo

  use TokenManager.TokenFactory
end
