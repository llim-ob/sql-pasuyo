import sys
import types
import unittest
from unittest.mock import patch

import auto


class OracleError(Exception):
    def __init__(self, code):
        super().__init__(types.SimpleNamespace(code=code))


class OracleCursor:
    def __init__(self, detail_tables, deleted_tables, inaccessible_tables, calls):
        self.detail_tables = detail_tables
        self.deleted_tables = deleted_tables
        self.inaccessible_tables = inaccessible_tables
        self.calls = calls
        self.row = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def execute(self, statement, **parameters):
        self.calls.append((statement, parameters))
        if "FROM ecs_header" in statement:
            self.row = (self.detail_tables[str(parameters["file_id"])],)
            return
        if "FROM user_tables" in statement:
            self.row = (1,) if parameters["table_name"] in self.deleted_tables else None
            return
        table_name = statement.split("FROM ", 1)[1].split(" WHERE", 1)[0]
        if table_name not in self.deleted_tables or table_name in self.inaccessible_tables:
            raise OracleError(942)

    def fetchone(self):
        return self.row


class OracleConnection:
    def __init__(self, detail_tables, deleted_tables, inaccessible_tables, calls):
        self.detail_tables = detail_tables
        self.deleted_tables = deleted_tables
        self.inaccessible_tables = inaccessible_tables
        self.calls = calls

    def cursor(self):
        return OracleCursor(
            self.detail_tables,
            self.deleted_tables,
            self.inaccessible_tables,
            self.calls,
        )

    def close(self):
        pass


def fake_oracledb(detail_tables, deleted_tables, inaccessible_tables=()):
    calls = []
    module = types.SimpleNamespace(
        Error=OracleError,
        DatabaseError=OracleError,
        is_thin_mode=lambda: False,
        makedsn=lambda host, port, service_name: (host, port, service_name),
        connect=lambda **kwargs: OracleConnection(
            detail_tables, deleted_tables, inaccessible_tables, calls
        ),
    )
    module.calls = calls
    return module


def delete_task(file_ids):
    return {
        "operation": "delete",
        "file_ids": file_ids,
        "feed_id": "335",
        "adapter_id": "335",
        "rename_to": "",
        "rename_pairs": [],
        "request_details": "",
    }


class AutomaticDeleteModeTests(unittest.TestCase):
    DB_ENV = {
        "DB_DATABASE": "database",
        "DB_HOST": "dbhost",
        "DB_PASSWORD": "password",
        "DB_PORT": "1521",
        "DB_USERNAME": "username",
    }

    def test_existing_deleted_table_selects_insert_mode(self):
        oracle = fake_oracledb(
            {"2730444": "ECS_DETAIL_TYPE335"},
            {"ECS_DETAIL_TYPE335_DELETED"},
        )
        with patch.dict(sys.modules, {"oracledb": oracle}), patch.dict(
            "os.environ", self.DB_ENV, clear=False
        ):
            resolved = auto.resolve_delete_mode(delete_task(["2730444"]))

        self.assertEqual(resolved["delete_mode"], "2")
        self.assertEqual(len(oracle.calls), 3)

    def test_missing_deleted_table_selects_create_mode(self):
        oracle = fake_oracledb({"2730444": "ECS_DETAIL_TYPE335"}, set())
        with patch.dict(sys.modules, {"oracledb": oracle}), patch.dict(
            "os.environ", self.DB_ENV, clear=False
        ):
            resolved = auto.resolve_delete_mode(delete_task(["2730444"]))

        self.assertEqual(resolved["delete_mode"], "1")

    def test_multiple_targets_share_one_detail_table_and_render_without_prompt(self):
        oracle = fake_oracledb(
            {
                "2730444": "ECS_DETAIL_TYPE335",
                "2676532": "ECS_DETAIL_TYPE335",
            },
            set(),
        )
        task = delete_task(["2730444", "2676532"])
        with patch.dict(sys.modules, {"oracledb": oracle}), patch.dict(
            "os.environ", self.DB_ENV, clear=False
        ):
            resolved = auto.resolve_delete_mode(task)
        rendered = auto.render_reference_template(resolved)

        self.assertEqual(resolved["delete_mode"], "1")
        self.assertIn("fileid IN (2730444, 2676532)", rendered)

    def test_mixed_detail_tables_are_rejected(self):
        oracle = fake_oracledb(
            {
                "2730444": "ECS_DETAIL_TYPE335",
                "2676532": "ECS_DETAIL_TYPE396",
            },
            set(),
        )
        with patch.dict(sys.modules, {"oracledb": oracle}), patch.dict(
            "os.environ", self.DB_ENV, clear=False
        ):
            with self.assertRaisesRegex(ValueError, "same detail table"):
                auto.resolve_delete_mode(delete_task(["2730444", "2676532"]))

    def test_inaccessible_deleted_table_does_not_select_create_mode(self):
        oracle = fake_oracledb(
            {"2730444": "ECS_DETAIL_TYPE335"},
            {"ECS_DETAIL_TYPE335_DELETED"},
            {"ECS_DETAIL_TYPE335_DELETED"},
        )
        with patch.dict(sys.modules, {"oracledb": oracle}), patch.dict(
            "os.environ", self.DB_ENV, clear=False
        ):
            with self.assertRaisesRegex(RuntimeError, "Could not check"):
                auto.resolve_delete_mode(delete_task(["2730444"]))

    def test_combined_render_keeps_delete_detail_table_out_of_reload_sql(self):
        task = {
            "operation": "reload-delete",
            "file_ids": ["2730444", "2676532"],
            "file_ids_by_operation": {
                "reload": ["2730444"],
                "delete": ["2676532"],
            },
            "feed_id": "335",
            "adapter_id": "335",
            "rename_to": "",
            "rename_pairs": [],
            "request_details": "",
            "delete_mode": "2",
            "delete_detail_table": "ECS_DETAIL_TYPE396",
            "is_ai_adapter": False,
        }

        rendered = auto.render_reference_template(task)

        reload_sql, delete_sql = rendered.split("## Delete", 1)
        self.assertIn("ecs_detail_type335", reload_sql)
        self.assertNotIn("ECS_DETAIL_TYPE396", reload_sql)
        self.assertIn("ECS_DETAIL_TYPE396", delete_sql)

    def test_delete_render_requires_resolved_mode(self):
        with self.assertRaisesRegex(ValueError, "delete mode must be resolved"):
            auto.render_reference_template(delete_task(["2730444"]))

    def test_ccs_delete_skips_delete_mode_resolution(self):
        task = {"operation": "ccs-delete", "file_ids": ["2784761"]}

        self.assertEqual(auto.resolve_delete_mode(task), task)


if __name__ == "__main__":
    unittest.main()
