import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "non_niq"))
from non_niq_embed import is_confirmed, _format_passage_text, _format_query_text

def test_confirmed_when_meta_is_labeling_source():
    assert is_confirmed('{"source": "labeling"}') is True

def test_confirmed_when_meta_is_human_qa():
    assert is_confirmed('{"name":"Aditya","email":"a@b.com","role":"ANALYST","timestamp":"2025-10-13T16:09:31.747Z"}') is True

def test_confirmed_when_meta_empty():
    assert is_confirmed("") is True  # legacy empty _meta rows are still confirmed human/original data

def test_confirmed_when_meta_is_nan_literal():
    assert is_confirmed("nan") is True  # malformed legacy value, not one of ours -- treat as confirmed, not excluded

def test_unconfident_agent_row_excluded():
    assert is_confirmed('{"source":"claude_code","qa_confidence":"unconfident","human_review":false}') is False

def test_confident_agent_row_confirmed():
    assert is_confirmed('{"source":"claude_code","qa_confidence":"confident"}') is True

def test_unconfident_terminal_human_review_still_excluded():
    assert is_confirmed('{"source":"claude_code","qa_confidence":"unconfident","human_review":true}') is False

def test_format_passage_text_for_indexed_corpus():
    """E5 asymmetric retrieval: indexed corpus uses 'passage:' prefix."""
    assert _format_passage_text("baby shampoo") == "passage: baby shampoo"

def test_format_query_text_for_search_queries():
    """E5 asymmetric retrieval: search queries use 'query:' prefix."""
    assert _format_query_text("baby shampoo") == "query: baby shampoo"

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
