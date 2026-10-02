defmodule IncidentRoom.DomainTest do
  use ExUnit.Case, async: true
  alias IncidentRoom.Incidents

  test "status graph closes resolved rooms" do
    assert Incidents.valid_transition?("investigating", "monitoring")
    assert Incidents.valid_transition?("monitoring", "resolved")
    assert Incidents.valid_transition?("monitoring", "investigating")
    refute Incidents.valid_transition?("investigating", "resolved")
    refute Incidents.valid_transition?("resolved", "investigating")
  end

  test "notes have nonblank bounded text and no NUL" do
    assert Incidents.valid_text?("Observed a recovery", 2000)
    refute Incidents.valid_text?("  ", 2000)
    refute Incidents.valid_text?(String.duplicate("x", 2001), 2000)
    refute Incidents.valid_text?("hidden" <> <<0>>, 2000)
  end

  test "Unicode limits count PostgreSQL codepoints, not graphemes" do
    assert Incidents.valid_text?(String.duplicate("e\u0301", 80), 160)
    refute Incidents.valid_text?(String.duplicate("e\u0301", 81), 160)
    assert Incidents.valid_text?(String.duplicate("🧑‍💻", 53), 160)
    refute Incidents.valid_text?(String.duplicate("🧑‍💻", 54), 160)
    assert {:error, :invalid_input} = Incidents.open(nil, [])
    assert {:error, :invalid_input} = Incidents.note(nil, nil, "body")
    assert {:error, :invalid_input} = Incidents.transition(nil, nil, nil)
  end
end
