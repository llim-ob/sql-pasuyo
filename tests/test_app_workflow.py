import io
import json
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import auto


LINK = "https://objectbright.teamwork.com/app/tasks/123"
ISSUE = "https://github.com/example/requests/issues/1"


class AppWorkflowTests(unittest.TestCase):
    def run_cli(self, *arguments, stdin=""):
        output = io.StringIO()
        with patch("sys.argv", ["auto.py", *arguments]), patch(
            "sys.stdin", io.StringIO(stdin)
        ), redirect_stdout(output):
            self.assertEqual(auto.main(), 0)
        return json.loads(output.getvalue())

    def test_preview_uses_ai_template_without_writing(self):
        task = {
            "title": "Reload file",
            "feed_id": "23",
            "adapter_id": "24",
            "file_ids": ["1234"],
        }
        with patch.object(auto, "fetch_task", return_value=task), patch.object(
            auto, "detect_ai_adapter", side_effect=lambda task: {**task, "is_ai_adapter": True}
        ), patch.object(auto, "github_request") as github, patch.object(
            auto, "teamwork_add_tag"
        ) as tag:
            preview = self.run_cli("--preview-json", LINK, "--reload")

        self.assertEqual(preview["task_id"], "123")
        self.assertEqual(preview["operation"], "reload")
        self.assertIn(
            (auto.TEMPLATE_DIR / "ai_reload.txt").read_text().splitlines()[0],
            preview["request_text"],
        )
        self.assertIn(preview["request_text"], preview["issue_body"])
        github.assert_not_called()
        tag.assert_not_called()

    def test_combined_blob_update_preview_keeps_combined_operation(self):
        task = {
            "task_id": "123",
            "link": LINK,
            "title": "Replace blob and delete",
            "operation": "reload-delete",
            "request_details": "For Reload / BLOB Update",
        }
        with patch.object(auto, "prepare_request", return_value=(task, "Combined request")):
            preview = self.run_cli("--preview-json", LINK)
        self.assertEqual(preview["operation"], "reload-delete")

    def test_publish_submits_reviewed_body_and_then_tags(self):
        for tag_error in (None, RuntimeError("Tagging unavailable")):
            with self.subTest(tag_error=tag_error):
                preview = {
                    "task_id": "123",
                    "title": "Reload file",
                    "issue_body": "The exact reviewed body",
                    "request_details": "For Reload / BLOB Update",
                }
                with patch.dict("os.environ", {"GITHUB_TOKEN": "test"}), patch.object(
                    auto, "github_request", return_value={"html_url": ISSUE}
                ) as github, patch.object(
                    auto, "teamwork_add_tag", side_effect=tag_error
                ) as tag, patch.object(auto, "fetch_task") as fetch:
                    result = self.run_cli("--publish-json", stdin=json.dumps(preview))

                self.assertEqual(github.call_args.args[-1]["body"], preview["issue_body"])
                self.assertEqual(result["issue_url"], ISSUE)
                self.assertEqual(result["tag_error"], str(tag_error) if tag_error else None)
                self.assertEqual(tag.call_args_list[0].args, ("123", auto.SQL_REQUEST_TAG))
                if tag_error is None:
                    self.assertEqual(tag.call_args_list[1].args, ("123", auto.BLOB_UPDATE_TAG))
                fetch.assert_not_called()
