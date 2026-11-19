"""Read a consistent snapshot from the project schema."""
import psycopg
from psycopg.rows import dict_row


QUERIES = {
    "topology": """
        WITH RECURSIVE ancestors AS (
            SELECT g.id, g.parent_id, g.code, g.group_type, ARRAY[g.id] AS path
            FROM project.node_group g
            JOIN project.node n ON n.node_group_id = g.id
            WHERE n.id = %(node)s
            UNION ALL
            SELECT g.id, g.parent_id, g.code, g.group_type, a.path || g.id
            FROM ancestors a JOIN project.node_group g ON g.id = a.parent_id
            WHERE NOT g.id = ANY(a.path)
        )
        SELECT id, parent_id, code, group_type FROM ancestors
        ORDER BY cardinality(path) DESC
    """,
    "components": """
        SELECT id, kind, local_index, model FROM project.component
        WHERE node_id = %(node)s ORDER BY kind, local_index
    """,
    "metrics": """
        SELECT DISTINCT mt.id, mt.code, mt.component_kind, mt.quantity, mt.unit
        FROM project.metric_type mt JOIN project.metric_source s ON s.metric_type_id = mt.id
        JOIN project.component c ON c.id = s.component_id
        WHERE c.node_id = %(node)s ORDER BY mt.code
    """,
    "snapshot": """
        SELECT c.id AS component_id, c.kind, c.local_index, mt.code, mt.unit,
               s.id AS source_id, s.source_key, t.id AS telemetry_id, t.ts, t.value
        FROM project.component c JOIN project.metric_type mt ON mt.component_kind = c.kind
        LEFT JOIN project.metric_source s ON s.component_id = c.id AND s.metric_type_id = mt.id
        LEFT JOIN project.telemetry t ON t.metric_source_id = s.id AND t.ts = %(ts)s
        WHERE c.node_id = %(node)s ORDER BY c.kind, c.local_index, mt.code
    """,
    "events": """
        SELECT id, node_id, occurred_at, severity, event_type, message
        FROM project.event WHERE node_id = %(node)s ORDER BY occurred_at, id
    """,
    "maintenance": """
        SELECT m.id, m.node_id, m.performed_at, m.maintenance_type, m.notes,
               e.id AS engineer_id, e.tab_no, e.full_name
        FROM project.maintenance m JOIN project.engineer e ON e.id = m.engineer_id
        WHERE m.node_id = %(node)s ORDER BY m.performed_at, m.id
    """,
    "resources": """
        SELECT mr.maintenance_id, r.id AS resource_id, r.code, r.name, mr.qty
        FROM project.maintenance_resource mr JOIN project.resource r ON r.id = mr.resource_id
        JOIN project.maintenance m ON m.id = mr.maintenance_id
        WHERE m.node_id = %(node)s ORDER BY mr.maintenance_id, r.id
    """,
    "documents": """
        SELECT id, node_id, document_type, title, url
        FROM project.document WHERE node_id = %(node)s ORDER BY id
    """,
}


def read_snapshot(dsn, hostname, timestamp):
    with psycopg.connect(dsn, row_factory=dict_row, connect_timeout=5) as connection:
        connection.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        connection.execute("SET LOCAL TIME ZONE 'UTC'")
        node = connection.execute(
            "SELECT id, hostname, description FROM project.node WHERE hostname = %s", (hostname,)
        ).fetchone()
        if node is None:
            return {"node": None}
        params = {"node": node["id"], "ts": timestamp}
        return {"node": node, **{
            name: connection.execute(sql, params).fetchall() for name, sql in QUERIES.items()
        }}
