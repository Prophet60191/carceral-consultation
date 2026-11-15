defmodule Claper.Accounts.PasswordPolicyTest do
  @moduledoc "Password rules (docs/SECURITY.md, NIST SP 800-63B-4 3.1.1.2)."
  use Claper.DataCase, async: false

  alias Claper.Accounts
  alias Claper.Accounts.User

  @good "a quiet lake at dawn"

  defp errors(attrs) do
    case Accounts.create_user(Map.merge(%{email: "sam.rivera@example.org"}, attrs)) do
      {:ok, _} -> []
      {:error, changeset} -> errors_on(changeset)[:password] || []
    end
  end

  describe "length" do
    test "15 characters at least, with no rules about character types" do
      assert [message] = errors(%{password: "fourteen chars"})
      assert message =~ "at least 15 characters"
      assert errors(%{password: "fifteen letters"}) == []
    end

    test "at most 72 bytes (bcrypt)" do
      assert [message] = errors(%{password: String.duplicate("a", 73)})
      assert message =~ "at most 72"
    end
  end

  describe "personal words" do
    test "the person's email, name or the app's name are refused, with the reason" do
      assert [message] = errors(%{password: "Sam.Rivera@Example.org"})
      assert message =~ "Don't use your name, your email address"
      assert [_] = errors(%{password: "sam.rivera-2026-2026!!"})

      {:ok, _} = Claper.Branding.update(%{"name" => "Northside Reentry Network"})
      on_exit(fn -> Claper.Branding.clear_cache() end)
      assert [_] = errors(%{password: "NorthsideReentryNetwork1"})
    end

    test "a password that only contains a personal word is fine" do
      assert errors(%{password: "sam walks by the lake"}) == []
    end
  end

  describe "known breaches (Have I Been Pwned)" do
    setup do
      config = Application.get_env(:claper, Claper.Accounts.PwnedPasswords)

      Application.put_env(
        :claper,
        Claper.Accounts.PwnedPasswords,
        Keyword.put(config, :enabled, true)
      )

      on_exit(fn -> Application.put_env(:claper, Claper.Accounts.PwnedPasswords, config) end)
    end

    # The service gets only the first 5 characters of the SHA-1 hash
    defp stub_service(breached_password, count) do
      hash = :crypto.hash(:sha, breached_password) |> Base.encode16()
      {prefix, suffix} = String.split_at(hash, 5)

      Req.Test.stub(Claper.Accounts.PwnedPasswords, fn conn ->
        assert conn.request_path == "/range/" <> prefix
        assert Plug.Conn.get_req_header(conn, "add-padding") == ["true"]

        Req.Test.text(
          conn,
          "0000000000000000000000000000000000A:0\r\n#{suffix}:#{count}\r\nFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:3"
        )
      end)
    end

    test "a breached password is refused, with the reason" do
      stub_service("correct horse battery staple", 1024)
      assert [message] = errors(%{password: "correct horse battery staple"})
      assert message =~ "appeared in a data breach"
    end

    test "padding entries (count 0) don't count" do
      stub_service("a quiet lake at dawn", 0)
      assert errors(%{password: @good}) == []
    end

    test "if the service can't be reached, the password is allowed" do
      Req.Test.stub(Claper.Accounts.PwnedPasswords, &Req.Test.transport_error(&1, :timeout))
      assert errors(%{password: @good}) == []
    end
  end

  test "server-made random passwords (outside sign-in) skip the chosen-password checks" do
    changeset =
      User.registration_changeset(
        %User{},
        %{
          email: "x@example.org",
          password: :crypto.strong_rand_bytes(32),
          is_randomized_password: true
        },
        require_names: false
      )

    assert changeset.valid?
  end
end
