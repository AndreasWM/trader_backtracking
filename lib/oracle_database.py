import os
import logging
import oracledb
from contextlib import contextmanager
from dataclasses import fields, is_dataclass
from typing import Any, Generator, Optional

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)


class OracleDatabase:
    """Wrapper für Oracle-Datenbankzugriffe mit sicherem Context-Management."""

    def __init__(self):
        self.ld_library_path: Optional[str] = os.getenv("LD_LIBRARY_PATH")
        self.user: Optional[str] = os.getenv("ORACLE_TRADER_USER")
        self.password: Optional[str] = os.getenv("ORACLE_TRADER_PW")
        self.service_alias: Optional[str] = os.getenv("ORACLE_TRADER_DSN")

        # Oracle Client initialisieren (optional)
        try:
            if self.ld_library_path:
                oracledb.init_oracle_client(lib_dir=self.ld_library_path)
        except Exception as e:
            log.warning("init_oracle_client fehlgeschlagen: %s", e)

        # Verbindung aufbauen
        try:
            self.connection: Optional[oracledb.Connection] = oracledb.connect(
                user=self.user,
                password=self.password,
                dsn=self.service_alias
            )
            log.info("Oracle-Verbindung hergestellt.")
        except oracledb.Error as e:
            log.error("Oracle-Verbindung fehlgeschlagen: %s", e)
            self.connection = None

    # --- interne Hilfsmethode ---
    def _ensure_connection(self) -> None:
        """Stellt sicher, dass eine aktive DB-Verbindung existiert."""
        if self.connection is None:
            raise RuntimeError("Keine aktive Oracle-Verbindung vorhanden.")

    # --- Cursor-Kontextmanager ---
    @contextmanager
    def cursor(self) -> Generator[oracledb.Cursor, None, None]:
        self._ensure_connection()
        cur: Optional[oracledb.Cursor] = None
        try:
            cur = self.connection.cursor()  # type: ignore[union-attr]
            yield cur
        finally:
            if cur is not None:
                try:
                    cur.close()
                except Exception as e:
                    log.debug("Fehler beim Schließen des Cursors: %s", e)

    # --- Standard Execute ---
    def execute(self, sql: str, params: Optional[list[Any]] = None, fetch: bool = False) -> Any:
        with self.cursor() as cur:
            cur.execute(sql, params or [])
            return cur.fetchall() if fetch else cur.rowcount

    # --- Safe Execute ---
    def safe_execute(
        self,
        sql: str,
        params: Optional[dict[str, Any]] = None,
        fetch: bool = False,
        commit: bool = False,
        auto_rollback: bool = False
    ) -> dict[str, Any]:
        try:
            with self.cursor() as cur:
                cur.execute(sql, params or [])
                rows = cur.fetchall() if fetch else None
                rowcount = cur.rowcount
                if commit:
                    self.commit()
                return {"success": True, "rows": rows, "rowcount": rowcount}
        except oracledb.Error as e:
            log.exception("DB-Fehler bei execute")
            if auto_rollback:
                try:
                    self.rollback()
                except Exception:
                    log.exception("Rollback fehlgeschlagen")
            return {"success": False, "error": str(e)}

    # --- Transaktions-Methoden ---
    def commit(self) -> None:
        if self.connection:
            try:
                self.connection.commit()
            except Exception:
                log.exception("Commit fehlgeschlagen")
                raise

    def rollback(self) -> None:
        if self.connection:
            try:
                self.connection.rollback()
            except Exception:
                log.exception("Rollback fehlgeschlagen")
                raise

    def close(self) -> None:
        if self.connection:
            try:
                self.connection.close()
            except Exception:
                log.exception("Connection close fehlgeschlagen")
            finally:
                self.connection = None

    # --- Kontextmanager-Integration ---
    def __enter__(self) -> "OracleDatabase":
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> bool:
        try:
            if exc_type:
                try:
                    self.rollback()
                except Exception:
                    log.exception("Rollback im __exit__ fehlgeschlagen")
            else:
                try:
                    self.commit()
                except Exception:
                    log.exception("Commit im __exit__ fehlgeschlagen")
        finally:
            self.close()
        return False

    # --- Transaktion als Contextmanager ---
    @contextmanager
    def transaction(self) -> Generator["OracleDatabase", None, None]:
        try:
            yield self
            self.commit()
        except Exception:
            self.rollback()
            raise

    # --- SELECT Shortcut ---
    def select(self, sql: str, params: Optional[list[Any]] = None) -> dict[str, Any]:
        return self.safe_execute(sql, params=params, fetch=True)

    # --- Bulk Insert ---
    def bulk_insert(
        self,
        sql: str,
        data: list[tuple[Any, ...]],
        commit: bool = True,
        batcherrors: bool = False,
        arraydmlrowcounts: bool = False
    ) -> dict[str, Any]:
        try:
            with self.cursor() as cur:
                cur.executemany(sql, data,
                                batcherrors=batcherrors,
                                arraydmlrowcounts=arraydmlrowcounts)
                if commit:
                    self.commit()

                result: dict[str, Any] = {"success": True, "rowcount": cur.rowcount}
                if arraydmlrowcounts:
                    result["rowcounts"] = cur.getarraydmlrowcounts()
                if batcherrors:
                    result["errors"] = cur.getbatcherrors()
                return result
        except oracledb.Error as e:
            log.exception("Bulk-Insert fehlgeschlagen")
            self.rollback()
            return {"success": False, "error": str(e)}

    # --- Bulk Insert aus Dataclasses ---
    def bulk_insert_from_dataclasses(
        self,
        sql: str,
        objects: list[Any],
        field_names: list[str],
        **kwargs: Any
    ) -> dict[str, Any]:
        if not objects:
            return {"success": True, "rowcount": 0}

        first = objects[0]
        if not is_dataclass(first):
            raise TypeError("Liste muss Dataclass-Instanzen enthalten")

        valid_fields = {f.name for f in fields(first)}
        cls_name = type(first).__name__

        for name in field_names:
            if name not in valid_fields:
                raise ValueError(f"Feld '{name}' existiert nicht in {cls_name}")

        data = [tuple(getattr(obj, name) for name in field_names) for obj in objects]
        return self.bulk_insert(sql, data, **kwargs)

    # --- Scalar-Select ---
    def select_scalar(self, sql: str) -> Any:
        result = self.select(sql)
        if result["success"] and result["rows"]:
            return result["rows"][0][0]
        return None
