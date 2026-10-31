import sys
import unittest
from unittest.mock import patch

import auto
from auto import analyze_task_hardcoded, render_reference_template, validate_task


CCS_TASK = {
    "task_id": "123",
    "title": "Protective CCS - Remove Duplicate - req by Jenna 10302026",
    "description": "Please remove ID 2784761 as this is a duplicate of 2785166",
    "feed_id": "",
    "adapter_id": "",
    "file_ids": ["2784761", "2785166"],
    "rename_from": "",
    "rename_to": "",
    "rename_pairs": [],
}


class CcsDeleteTests(unittest.TestCase):
    def test_ccs_duplicate_delete_uses_only_target_file_id(self):
        analysis = analyze_task_hardcoded(CCS_TASK)

        self.assertEqual(analysis["operation"], "ccs-delete")

        validated = validate_task(CCS_TASK, analysis)

        self.assertEqual(validated["file_ids"], ["2784761"])
        self.assertEqual(
            render_reference_template(validated),
            """```sql
DELETE FROM PIMAGECCS WHERE IMAGEID in (2784761);
DELETE FROM PIMAGECATALOG WHERE IMAGEID in (2784761);
DELETE FROM TXNITEM WHERE IMAGEID in (2784761);
DELETE FROM CCSDETAIL WHERE IMAGEID in (2784761);
COMMIT
```""",
        )

    def test_ccs_without_delete_is_not_ccs_delete(self):
        task = {
            **CCS_TASK,
            "title": "Protective CCS review",
            "description": "Please review the CCS record.",
        }

        self.assertNotEqual(analyze_task_hardcoded(task)["operation"], "ccs-delete")

    def test_ccs_classification_stays_deterministic_when_qwen_is_configured(self):
        with patch.object(auto, "QWEN_API_KEY", "configured"), patch.object(
            auto, "qwen_chat", return_value='{"operation": "delete"}'
        ) as qwen_chat:
            analysis = auto.analyze_task(CCS_TASK)

        self.assertEqual(analysis["operation"], "ccs-delete")
        qwen_chat.assert_not_called()

    def test_ccs_duplicate_reference_can_be_in_a_different_field(self):
        task = {
            **CCS_TASK,
            "title": "Protective CCS - Remove duplicate",
            "description": "Target ID 2784761 is a duplicate of 2785166",
        }

        validated = validate_task(task, analyze_task_hardcoded(task))

        self.assertEqual(validated["file_ids"], ["2784761"])

    def test_normal_delete_still_requires_feed_and_adapter(self):
        task = {**CCS_TASK, "title": "Remove file 2784761"}

        with self.assertRaisesRegex(ValueError, "missing required feed ID, adapter ID"):
            validate_task(task, analyze_task_hardcoded(task))

    def test_normal_delete_keeps_existing_duplicate_reference_behavior(self):
        task = {
            **CCS_TASK,
            "title": "Remove file 2784761 as this is a duplicate of 2785166",
            "description": "",
            "feed_id": "396",
            "adapter_id": "396",
        }

        validated = validate_task(task, analyze_task_hardcoded(task))

        self.assertEqual(validated["file_ids"], ["2784761", "2785166"])

    def test_main_does_not_calculate_ccs_detail_table(self):
        task = {**CCS_TASK, "task_id": "123"}
        with patch.object(sys, "argv", ["auto.py", "https://example.test/tasks/123"]), patch.object(
            auto, "parse_teamwork_link", return_value={"task_id": "123", "link": "task-link"}
        ), patch.object(auto, "fetch_task", return_value=task), patch.object(
            auto, "append_database_file_extension", side_effect=lambda value: value
        ), patch.object(auto, "detect_ai_adapter", side_effect=lambda value: value), patch.object(
            auto, "render_reference_template", return_value="```sql\nCCS SQL\n```"
        ), patch.object(auto, "add_teamwork_tags"), patch.object(
            auto, "create_github_issue", return_value="https://github.test/issues/1"
        ), patch.object(auto, "detail_table_name", side_effect=AssertionError("CCS has no detail table")):
            self.assertEqual(auto.main(), 0)


if __name__ == "__main__":
    unittest.main()
