#!/usr/bin/env python3
"""gen-db-schema-ref.py — Generate schema reference from code sources.

Parses:
  - her-web/src/config/db/schema.postgres.ts (Drizzle ORM, camelCase → snake_case)
  - her-gateway/model/*.go (GORM tags)

Outputs pipe-delimited lines: table_name|column_name|source
Compare against runtime: her-db <env> --schema <table>

Usage:
  python3 gen-db-schema-ref.py [--her-web PATH] [--her-gateway PATH]
"""
import re, sys, os, argparse

def parse_drizzle_schema(path):
    """Parse schema.postgres.ts → {table: [columns]}"""
    tables = {}
    if not os.path.exists(path):
        print(f"WARN: {path} not found", file=sys.stderr)
        return tables

    with open(path) as f:
        content = f.read()

    # Match: export const varName = table('db_table_name', { ... })
    # Extract table name from first string arg to table()
    table_pattern = re.compile(
        r"export\s+const\s+\w+\s*=\s*table\(\s*['\"](\w+)['\"]",
        re.MULTILINE
    )
    # Match column definitions: propName: type('db_col_name')
    col_pattern = re.compile(
        r"(\w+)\s*:\s*(?:text|boolean|integer|bigint|timestamp)\(['\"](\w+)['\"]\)"
    )

    # Split by export const to get each table block
    blocks = re.split(r'(?=export\s+const\s+\w+\s*=\s*table\()', content)

    for block in blocks:
        table_match = table_pattern.search(block)
        if not table_match:
            continue
        table_name = table_match.group(1)
        columns = []
        for col_match in col_pattern.finditer(block):
            _js_name = col_match.group(1)  # noqa: F841 — kept for debugging
            db_name = col_match.group(2)
            columns.append(db_name)
        if columns:
            tables[table_name] = columns

    return tables


def parse_gorm_models(model_dir):
    """Parse Go model files with GORM tags → {table: [columns]}"""
    tables = {}
    if not os.path.exists(model_dir):
        print(f"WARN: {model_dir} not found", file=sys.stderr)
        return tables

    # GORM tag pattern: gorm:"column:col_name..."
    col_pattern = re.compile(r'gorm:"[^"]*column:(\w+)')
    # Table name from TableName() method
    tablename_pattern = re.compile(r'func\s+\(\w+\s+(\w+)\)\s+TableName\(\)\s+string\s*\{[^}]*return\s+"(\w+)"')

    for fname in os.listdir(model_dir):
        if not fname.endswith('.go'):
            continue
        filepath = os.path.join(model_dir, fname)
        with open(filepath) as f:
            content = f.read()

        # Find struct definitions and their GORM columns
        struct_pattern = re.compile(
            r'type\s+(\w+)\s+struct\s*\{(.*?)\n\}',
            re.DOTALL
        )
        # Map struct name → table name via TableName()
        struct_to_table = {}
        for m in tablename_pattern.finditer(content):
            struct_to_table[m.group(1)] = m.group(2)

        for m in struct_pattern.finditer(content):
            struct_name = m.group(1)
            body = m.group(2)
            columns = col_pattern.findall(body)
            if not columns:
                continue
            # Use TableName() if available, else lowercase struct name + 's'
            table_name = struct_to_table.get(struct_name, struct_name.lower() + 's')
            tables[table_name] = columns

    return tables


def main():
    parser = argparse.ArgumentParser(description='Generate schema reference from code')
    parser.add_argument('--her-web', default=os.path.expanduser('~/Documents/her-source/her-web'))
    parser.add_argument('--her-gateway', default=os.path.expanduser('~/Documents/her-source/her-gateway'))
    args = parser.parse_args()

    schema_path = os.path.join(args.her_web, 'src/config/db/schema.postgres.ts')
    model_dir = os.path.join(args.her_gateway, 'model')

    drizzle = parse_drizzle_schema(schema_path)
    gorm = parse_gorm_models(model_dir)

    print("# Code-derived schema reference")
    print(f"# her-web tables: {len(drizzle)}, gateway tables: {len(gorm)}")
    print("# Format: table|column|source")
    print()

    for table in sorted(drizzle):
        for col in drizzle[table]:
            print(f"{table}|{col}|drizzle")

    for table in sorted(gorm):
        for col in gorm[table]:
            print(f"{table}|{col}|gorm")


if __name__ == '__main__':
    main()
